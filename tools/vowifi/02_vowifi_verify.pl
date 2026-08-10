#!/usr/bin/env perl
use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);


my $TIMEOUT = 5;

# 云南电信DNS
my @dns_servers;
if (@ARGV) {
    foreach my $addr (@ARGV) {
        push @dns_servers, { name => "自定义DNS", address => $addr };
    }
} else {
    @dns_servers = (
        { name => "云南电信DNS 1", address => "240e:52:4800::8888" },
        { name => "云南电信DNS v4", address => "222.172.200.68" },
        { name => "阿里云 DNS v4", address => "223.5.5.5" },
        { name => "阿里云 DNS", address => "2400:3200::1" },
        { name => "CNNIC DNS", address => "2402:4e00::" },
        { name => "Google DNS64", address => "2001:4860:4860::6464" },
    );
}

# VoWiFi相关域名
my @domains = (
    "epdg.epc.mnc011.mcc460.pub.3gppnetwork.org",
);

# 历史对比基准（初始为空；如需对比历史，可手动填入之前解析出的真实IP）
my %previous_ips = ();

print "=" x 80 . "\n";
print "VoWiFi域名正向解析验证 (A记录 + AAAA记录)\n";
print "使用多个DNS交叉对比\n";
print "=" x 80 . "\n\n";

foreach my $dns (@dns_servers) {
    printf "%-25s [%s]\n", $dns->{name}, $dns->{address};
    print "-" x 80 . "\n";
    
    my ($dest, $family, $err) = dns_sockaddr($dns->{address}, 53);
    if (!defined $dest) {
        print "  [错误] 地址格式无效: $err\n\n";
        next;
    }
    
    my $sock;
    socket($sock, $family, SOCK_DGRAM, IPPROTO_UDP) or do {
        print "  [错误] 无法创建socket\n\n";
        next;
    };
    
    my $timeval = pack("L!L!", $TIMEOUT, 0);
    setsockopt($sock, SOL_SOCKET, SO_RCVTIMEO, $timeval);
    
    foreach my $domain (@domains) {
        # A记录查询
        my $query_a = build_dns_query($domain, 1);
        my $dest_addr = $dest;
        
        my $sent = send($sock, $query_a, 0, $dest_addr);
        next if (!$sent || $sent != length($query_a));
        
        my $response;
        my $from = recv($sock, $response, 512, 0);
        next if (!$from);
        
        my @ips = parse_dns_response($response, 1);
        
        if (@ips) {
            my @valid = grep { $_ ne "127.0.0.1" } @ips;
            my $status = check_ips($domain, \@valid);
            printf "  A   %-50s\n      → %s %s\n", $domain, join(", ", @valid), $status;
        } else {
            printf "  A   %-50s → [无记录]\n", $domain;
        }
        
        # AAAA记录查询
        my $query_aaaa = build_dns_query($domain, 28);
        $dest_addr = $dest;
        
        $sent = send($sock, $query_aaaa, 0, $dest_addr);
        next if (!$sent || $sent != length($query_aaaa));
        
        $response = "";
        $from = recv($sock, $response, 512, 0);
        next if (!$from);
        
        my @ips6 = parse_dns_response($response, 28);
        
        if (@ips6) {
            my @valid6 = grep { $_ ne "::1" && $_ ne "0:0:0:0:0:0:0:1" } @ips6;
            if (@valid6) {
                printf "  AAAA %-50s\n      → %s\n", $domain, join(", ", @valid6);
            }
        }
    }
    
    close($sock);
    print "\n";
}

print "=" x 80 . "\n";
print "测试完成\n";
print "=" x 80 . "\n";

sub check_ips {
    my ($domain, $current_ips) = @_;
    my $prev = $previous_ips{$domain};
    return "" unless $prev;
    
    my %prev_set = map { $_ => 1 } @$prev;
    my @new = grep { !$prev_set{$_} } @$current_ips;
    
    if (@new) {
        return "[⚠️ 新增IP: " . join(", ", @new) . "]";
    } else {
        return "[✓ 与之前一致]";
    }
}
 

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

sub inet_pton_ipv6 {
    my ($addr) = @_;
    if ($addr =~ /::/) {
        my @parts = split(/::/, $addr, 2);
        my @left = $parts[0] ? split(/:/, $parts[0]) : ();
        my @right = $parts[1] ? split(/:/, $parts[1]) : ();
        my $missing = 8 - scalar(@left) - scalar(@right);
        return undef if ($missing < 0);
        my @mid = ("0") x $missing if $missing > 0;
        my @full = (@left, @mid, @right);
        return undef if (scalar(@full) != 8);
        my $bytes = "";
        foreach my $part (@full) {
            $part = "0" if (!defined $part || $part eq "");
            return undef if ($part =~ /[^0-9a-fA-F]/);
            $bytes .= pack("n", hex($part));
        }
        return $bytes;
    } else {
        my @parts = split(/:/, $addr);
        return undef if (scalar(@parts) != 8);
        my $bytes = "";
        foreach my $part (@parts) {
            $part = "0" if (!defined $part || $part eq "");
            return undef if ($part =~ /[^0-9a-fA-F]/);
            $bytes .= pack("n", hex($part));
        }
        return $bytes;
    }
}

sub build_dns_query {
    my ($domain, $type) = @_;
    $type ||= 1;
    my $tid = int(rand(65535));
    my $header = pack("n6", $tid, 0x0100, 1, 0, 0, 0);
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
