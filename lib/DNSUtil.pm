package DNSUtil;
# ============================================================================
# DNS 工具函数库（纯函数，无网络 IO，可单元测试）
# 用法: use FindBin; use lib "$FindBin::Bin/../lib"; use DNSUtil;
# 提供: dns_sockaddr / inet_pton_ipv6 / build_dns_query / parse_dns_response
# 来源: 从 tools/vowifi/01_resolve_vowifi.pl 提取（其余脚本副本后续迁移）
# ============================================================================
use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use Exporter 'import';

our @EXPORT = qw(dns_sockaddr inet_pton_ipv6 build_dns_query parse_dns_response);

# 自动识别IPv4/IPv6地址，返回 (sockaddr, family, error)
sub dns_sockaddr {
    my ($addr, $port) = @_;
    if ($addr =~ /^\d{1,3}(?:\.\d{1,3}){3}$/) {
        my $ip = inet_aton($addr);
        return (undef, undef, "IPv4地址格式无效: $addr") unless defined $ip;
        return (pack_sockaddr_in($port, $ip), AF_INET, undef);
    }
    my $ip = inet_pton_ipv6($addr);
    return (undef, undef, "IPv6地址格式无效: $addr") unless defined $ip;
    return (pack("S n N a16 N", AF_INET6, $port, 0, $ip, 0), AF_INET6, undef);
}

# 手动实现 inet_pton for IPv6
sub inet_pton_ipv6 {
    my ($addr) = @_;

    if ($addr =~ /::/) {
        my @parts = split(/::/, $addr, 2);
        my @left = $parts[0] ? split(/:/, $parts[0]) : ();
        my @right = $parts[1] ? split(/:/, $parts[1]) : ();
        # hex 合法性校验（perl hex() 对非法字符只警告不报错，需显式拒绝）
        for my $p (@left, @right) {
            return undef if defined($p) && $p =~ /[^0-9a-fA-F]/;
        }
        my $missing = 8 - scalar(@left) - scalar(@right);
        my @mid = ("0") x $missing if $missing > 0;
        my @full = (@left, @mid, @right);

        my $bytes = "";
        foreach my $part (@full) {
            $part = "0" if (!defined $part || $part eq "");
            my $val = hex($part);
            $bytes .= pack("n", $val);
        }
        return $bytes;
    } else {
        my @parts = split(/:/, $addr);
        return undef if (scalar(@parts) != 8);
        # hex 合法性校验
        for my $p (@parts) {
            return undef if defined($p) && $p =~ /[^0-9a-fA-F]/;
        }

        my $bytes = "";
        foreach my $part (@parts) {
            $part = "0" if (!defined $part || $part eq "");
            my $val = hex($part);
            $bytes .= pack("n", $val);
        }
        return $bytes;
    }
}

# Build DNS query
sub build_dns_query {
    my ($domain, $type) = @_;
    $type ||= 1;  # Default A record

    my $tid = int(rand(65535));

    my $header = pack("n6",
        $tid, 0x0100, 1, 0, 0, 0
    );

    my $qname = "";
    foreach my $label (split(/\./, $domain)) {
        my $len = length($label);
        $len = 63 if ($len > 63);
        $qname .= pack("C", $len) . substr($label, 0, $len);
    }
    $qname .= pack("C", 0);

    my $qtype_class = pack("nn", $type, 1);

    return $header . $qname . $qtype_class;
}

# Parse DNS response
sub parse_dns_response {
    my ($response, $expected_type) = @_;
    $expected_type ||= 1;
    my @ips;

    return @ips if (length($response) < 12);

    my ($id, $flags, $qdcount, $ancount) = unpack("n4", substr($response, 0, 12));

    my $rcode = $flags & 0x000F;
    my $qr = ($flags >> 15) & 1;
    return @ips if (!$qr || $rcode != 0);

    my $offset = 12;

    for (my $i = 0; $i < $qdcount && $offset < length($response); $i++) {
        while ($offset < length($response)) {
            my $byte = unpack("C", substr($response, $offset, 1));
            $offset++;
            last if ($byte == 0);
            if ($byte >= 192) { $offset++; last; }
            $offset += $byte;
        }
        $offset += 4;
    }

    for (my $i = 0; $i < $ancount && $offset < length($response); $i++) {
        while ($offset < length($response)) {
            my $byte = unpack("C", substr($response, $offset, 1));
            if ($byte >= 192) { $offset += 2; last; }
            elsif ($byte == 0) { $offset++; last; }
            else { $offset += $byte + 1; }
        }

        last if ($offset + 10 > length($response));

        my ($type, $class, $ttl, $rdlength) = unpack("nnNn", substr($response, $offset, 10));
        $offset += 10;
        last if ($offset + $rdlength > length($response));

        if ($type == 1 && $rdlength == 4) {
            my $ip = inet_ntoa(substr($response, $offset, 4));
            push @ips, $ip if defined $ip;
        }
        elsif ($type == 28 && $rdlength == 16) {
            my @parts = unpack("n8", substr($response, $offset, 16));
            my $ipv6 = join(":", map { sprintf("%x", $_) } @parts);
            push @ips, $ipv6;
        }

        $offset += $rdlength;
    }

    return @ips;
}

1;
