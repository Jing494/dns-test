#!/usr/bin/env perl
use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);


# 设置超时（秒）
my $TIMEOUT = 2;

# 测试的DNS服务器
my @dns_servers;
if (@ARGV) {
    foreach my $addr (@ARGV) {
        push @dns_servers, { name => "自定义DNS", address => $addr };
    }
} else {
    @dns_servers = (
        { name => "电信DNS 1", address => "240e:52:4800::8888" },
        { name => "电信DNS 2", address => "240e:52:4000::8888" },
        { name => "云南电信 v4", address => "222.172.200.68" },
        { name => "阿里 DNS v4", address => "223.5.5.5" },
        { name => "CNNIC DNS",  address => "2402:4e00::" },
    );
}

# 中国电信VoWiFi相关域名
my @domains = (
    "epdg.epc.mnc000.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc001.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc002.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc003.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc004.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc005.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc006.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc007.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc008.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc009.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc010.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc011.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc012.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc013.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc014.mcc460.pub.3gppnetwork.org",
    "epdg.epc.mnc015.mcc460.pub.3gppnetwork.org",
    "epdg.epc.chinatelecom.cn",
    "epdg.epc.chn",
    "epdg.epc.telecom.cn",
    "vowifi.chinatelecom.cn",
    "vowifi.telecom.cn",
    "vowifi.189.cn",
    "epdg.epc.mcc460.mnc000.pub.3gppnetwork.org",
    "epdg.epc.mcc460.mnc001.pub.3gppnetwork.org",
);

print "=" x 80 . "\n";
print "中国电信VoWiFi ePDG域名解析测试\n";
print "=" x 80 . "\n\n";
$| = 1;  # 实时输出，避免管道缓冲导致看不到进度

# 为每个DNS服务器测试
foreach my $dns (@dns_servers) {
    print "-" x 80 . "\n";
    printf "DNS服务器: %s [%s]\n", $dns->{name}, $dns->{address};
    print "-" x 80 . "\n";
    
    # 自动识别IPv4/IPv6地址
    my ($dest, $family, $err) = dns_sockaddr($dns->{address}, 53);
    if (!defined $dest) {
        printf "  [错误] 地址格式无效: %s (%s)\n\n", $dns->{address}, $err;
        next;
    }
    
    # 创建UDP socket
    my $sock;
    socket($sock, $family, SOCK_DGRAM, IPPROTO_UDP) or do {
        printf "  [错误] 无法创建socket: $!\n\n";
        next;
    };
    
    # 设置接收超时
    my $timeval = pack("L!L!", $TIMEOUT, 0);
    setsockopt($sock, SOL_SOCKET, SO_RCVTIMEO, $timeval) or warn "设置超时失败: $!";
    
    my $success_a = 0;
    my $success_aaaa = 0;
    my $total = scalar @domains;
    my %a_timeout;  # A轮超时的域名，AAAA轮跳过（省时间）
    
    # 为每个域名测试
    foreach my $domain (@domains) {
        # 构造DNS A记录查询
        my $query = build_dns_query($domain, 1);  # Type A
        
        # 构建目标地址
        my $dest_addr = $dest;
        
        # 发送查询
        my $sent = send($sock, $query, 0, $dest_addr);
        
        if (!$sent || $sent != length($query)) {
            next;  # 静默跳过
        }
        
        # 接收响应
        my $response;
        my $from = recv($sock, $response, 512, 0);
        
        if (!$from) {
            $a_timeout{$domain} = 1;  # 标记超时，AAAA轮跳过
            next;
        }
        
        # 解析响应 - A记录
        my @ips = parse_dns_response($response, 1);
        
        if (@ips) {
            printf "  %-55s -> %s\n", $domain, join(", ", @ips);
            $success_a++;
        }
    }
    
    # 再用AAAA记录类型测试（跳过A轮超时的域名）
    foreach my $domain (@domains) {
        next if $a_timeout{$domain};
        my $query = build_dns_query($domain, 28);  # Type AAAA
        my $dest_addr = $dest;
        
        my $sent = send($sock, $query, 0, $dest_addr);
        next if (!$sent || $sent != length($query));
        
        my $response;
        my $from = recv($sock, $response, 512, 0);
        next if (!$from);
        
        my @ips = parse_dns_response($response, 28);
        
        if (@ips) {
            printf "  %-55s -> %s (AAAA)\n", $domain, join(", ", @ips);
            $success_aaaa++;
        }
    }
    
    close($sock);
    
    printf "\n成功解析: A记录 %d/%d, AAAA记录 %d/%d\n\n", $success_a, $total, $success_aaaa, $total;
}

print "=" x 80 . "\n";
print "测试完成\n";
print "=" x 80 . "\n";

# 手动实现inet_pton for IPv6 

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
