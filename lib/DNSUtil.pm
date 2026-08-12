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

our @EXPORT = qw(dns_sockaddr inet_pton_ipv6 build_dns_query parse_dns_response check_ips
                 build_ptr_query parse_ptr_response_simple build_reverse_name expand_ipv6);

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

# IP一致性对比（纯函数：prev_ref 为历史 IP 数组引用；返回状态文字）
sub check_ips {
    my ($domain, $current_ips, $prev_ref) = @_;
    return "" unless $prev_ref;
    my %prev_set = map { $_ => 1 } @$prev_ref;
    my @new = grep { !$prev_set{$_} } @$current_ips;
    if (@new) {
        return "[⚠️ 新增IP: " . join(", ", @new) . "]";
    } else {
        return "[✓ 与之前一致]";
    }
}

# 构建 PTR 查询（Type PTR = 12）
sub build_ptr_query {
    my ($reverse) = @_;
    my $tid = int(rand(65535));
    my $header = pack("n6", $tid, 0x0100, 1, 0, 0, 0);
    my $qname = "";
    foreach my $label (split(/\./, $reverse)) {
        my $len = length($label);
        $len = 63 if ($len > 63);
        $qname .= pack("C", $len) . substr($label, 0, $len);
    }
    $qname .= pack("C", 0);
    my $qtype_class = pack("nn", 12, 1);  # Type PTR = 12
    return $header . $qname . $qtype_class;
}

# 简化版 PTR 响应解析（仅提取第一个域名；rdata 为压缩域名时解引用）
sub parse_ptr_response_simple {
    my ($response) = @_;

    return () if (length($response) < 12);

    my ($id, $flags, $qdcount, $ancount) = unpack("n4", substr($response, 0, 12));
    my $rcode = $flags & 0x000F;
    my $qr = ($flags >> 15) & 1;
    return () if (!$qr || $rcode != 0);

    my $offset = 12;

    # Skip question section
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

    # Parse answer section（PTR 的 rdata 才是目标域名，需解析 rdata）
    my @names;
    for (my $i = 0; $i < $ancount && $offset < length($response); $i++) {
        # 跳过 owner name（可能含压缩指针）
        my $pos = $offset;
        my $guard = 0;
        while ($pos < length($response) && $guard < 20) {
            my $byte = unpack("C", substr($response, $pos, 1));
            if ($byte == 0) { $pos++; last; }
            if ($byte >= 192) { $pos += 2; last; }
            $pos += $byte + 1;
            $guard++;
        }
        $offset = $pos;
        last if ($offset + 10 > length($response));
        my ($type, $class, $ttl, $rdlength) = unpack("nnNn", substr($response, $offset, 10));
        $offset += 10;
        last if ($offset + $rdlength > length($response));

        if ($type == 12) {
            # PTR 的 rdata 是压缩域名，解引用完整解析
            my $rdata_name = "";
            my $rpos = $offset;
            my $rguard = 0;
            while ($rpos < length($response) && $rguard < 20) {
                my $byte = unpack("C", substr($response, $rpos, 1));
                if ($byte == 0) { $rpos++; last; }
                if ($byte >= 192) {
                    last if ($rpos + 1 >= length($response));
                    my $ptr = (($byte & 0x3F) << 8) | unpack("C", substr($response, $rpos + 1, 1));
                    last if ($ptr >= length($response));
                    $rpos = $ptr;
                    $rguard++;
                    next;
                }
                $rpos++;
                if ($rpos + $byte <= length($response)) {
                    $rdata_name .= substr($response, $rpos, $byte) . "." if $byte > 0;
                    $rpos += $byte;
                }
            }
            $rdata_name =~ s/\.$//;
            push @names, $rdata_name if $rdata_name;
        }

        $offset += $rdlength;
    }

    return @names;
}

# 构造反向解析域名（v4→in-addr.arpa，v6→ip6.arpa）
sub build_reverse_name {
    my ($ip) = @_;
    if ($ip =~ /:/) {
        my $expanded = expand_ipv6($ip);
        return undef unless defined $expanded;
        my $rev = join(".", reverse split(//, $expanded)) . ".ip6.arpa";
        return $rev;
    } else {
        my @octets = split(/\./, $ip);
        return undef unless @octets == 4;
        return join(".", reverse @octets) . ".in-addr.arpa";
    }
}

# 展开 IPv6 为 32 个 hex 字符
sub expand_ipv6 {
    my ($addr) = @_;
    my $bytes = inet_pton_ipv6($addr);
    return undef unless defined $bytes;
    return join("", map { sprintf("%04x", $_) } unpack("n8", $bytes));
}

1;

__END__

=head1 NAME

DNSUtil - DNS 报文工具函数库（纯函数，无网络 IO）

=head1 SYNOPSIS

    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use DNSUtil;

    my ($sockaddr, $family, $err) = dns_sockaddr("8.8.8.8", 53);
    my $query = build_dns_query("www.baidu.com", 1);
    my @ips = parse_dns_response($response, 1);

=head1 DESCRIPTION

提供 DNS 查询报文的构建、响应解析、地址转换等纯函数，供各 perl 脚本共用。
无网络 IO、无外部依赖（仅 Socket 核心模块），可单元测试（tests/01_dnsutil.t）。

=head1 FUNCTIONS

=head2 dns_sockaddr($addr, $port)

自动识别 IPv4/IPv6 地址，返回 (sockaddr, family, error)；非法地址 error 非空。

=head2 inet_pton_ipv6($addr)

IPv6 字符串转 16 字节二进制（支持 :: 压缩）；非法（非 hex、段数错误）返回 undef。

=head2 build_dns_query($domain, $type)

构建 DNS 查询报文（$type 默认 1=A；28=AAAA）。

=head2 parse_dns_response($response, $expected_type)

解析 DNS 响应中的 A/AAAA 记录，返回 IP 列表；非响应/NXDOMAIN/短包返回空。

=head2 check_ips($domain, $current_ips, $prev_ref)

IP 一致性对比（$prev_ref 为历史 IP 数组引用）；无变化返回一致标记，有新增返回提示。

=head2 build_ptr_query($reverse)

构建 PTR 反向查询报文（Type PTR=12）。

=head2 parse_ptr_response_simple($response)

解析 PTR 响应中的目标域名（支持 rdata 压缩指针解引用），返回域名列表。

=head2 build_reverse_name($ip)

构造反向解析域名：IPv4 → in-addr.arpa，IPv6 → ip6.arpa；非法返回 undef。

=head2 expand_ipv6($addr)

展开 IPv6 为 32 个 hex 字符；非法返回 undef。

=head1 TESTING

    perl -Ilib tests/01_dnsutil.t

=head1 SEE ALSO

L<Socket>

=cut
