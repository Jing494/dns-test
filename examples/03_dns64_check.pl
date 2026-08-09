#!/usr/bin/env perl
# 示例3: DNS64支持检测
# 功能: 检测DNS服务器是否支持DNS64（合成AAAA记录）
# 运行: perl 03_dns64_check.pl [DNS1] [DNS2] ... 不传默认4个公共DNS

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);

# 配置: 待检测的DNS服务器
my @DNS_SERVERS;
if (@ARGV) {
    foreach my $addr (@ARGV) {
        push @DNS_SERVERS, { name => "自定义DNS", address => $addr };
    }
} elsif ($ENV{DNS_LIST}) {
    # 环境变量 DNS_LIST 逗号分隔
    foreach my $addr (split(/,/, $ENV{DNS_LIST})) {
        push @DNS_SERVERS, { name => "自定义DNS", address => $addr };
    }
} else {
    @DNS_SERVERS = (
        { name => "Google DNS64", address => "2001:4860:4860::6464" },
        { name => "Cloudflare DNS64", address => "2606:4700:4700::64" },
        { name => "云南电信DNS(对照)", address => "222.172.200.68" },
        { name => "云南电信DNS v6(对照)", address => "240e:52:4800::8888" },
    );
}

# 测试域名（只有IPv4的域名）
my @DOMAINS = ("v4.ipv6test.app", "www.baidu.com", "www.qq.com");

# IPv6地址转换 

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

# 构建DNS查询
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

# 解析DNS响应
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
        
        if ($type == 28 && $rdlength == 16) {
            my @parts = unpack("n8", substr($response, $offset, 16));
            push @ips, join(":", map { sprintf("%x", $_) } @parts);
        }
        $offset += $rdlength;
    }
    return @ips;
}

# 检查是否是DNS64合成地址
sub is_dns64_synthesized {
    my ($ipv6) = @_;
    return ($ipv6 =~ /^64:ff9b:0:0:0:0:/i || $ipv6 =~ /^64:ff9b::/i);
}

# 从DNS64地址提取嵌入的IPv4
sub extract_ipv4_from_dns64 {
    my ($ipv6) = @_;
    if ($ipv6 =~ /:([0-9a-f]+):([0-9a-f]+)$/i) {
        my $hex1 = hex($1);
        my $hex2 = hex($2);
        return sprintf("%d.%d.%d.%d", ($hex1 >> 8) & 0xFF, $hex1 & 0xFF, ($hex2 >> 8) & 0xFF, $hex2 & 0xFF);
    }
    return "?";
}

# 主程序
print "=" x 70 . "\n";
print "示例3: DNS64支持检测\n";
print "=" x 70 . "\n\n";

foreach my $dns (@DNS_SERVERS) {
    printf "%-25s [%s]\n", $dns->{name}, $dns->{address};
    print "-" x 70 . "\n";
    
    my ($dest, $family, $err) = dns_sockaddr($dns->{address}, 53);
    if (!defined $dest) {
        print "  [错误] $err\n\n";
        next;
    }
    
    my $sock;
    socket($sock, $family, SOCK_DGRAM, IPPROTO_UDP) or do {
        print "  [错误] 无法创建socket\n\n";
        next;
    };
    setsockopt($sock, SOL_SOCKET, SO_RCVTIMEO, pack("L!L!", 3, 0));
    
    my $has_dns64 = 0;
    
    foreach my $domain (@DOMAINS) {
        my $query = build_dns_query($domain, 28);  # AAAA记录
        my $dest_addr = $dest;
        send($sock, $query, 0, $dest_addr);
        
        my $response;
        my $from = recv($sock, $response, 512, 0);
        
        if ($from) {
            my @ips = parse_dns_response($response, 28);
            if (@ips) {
                foreach my $ip (@ips) {
                    if (is_dns64_synthesized($ip)) {
                        my $embedded = extract_ipv4_from_dns64($ip);
                        printf "  %-25s → %s [DNS64✓ 嵌入IPv4: %s]\n", $domain, $ip, $embedded;
                        $has_dns64++;
                    } else {
                        printf "  %-25s → %s [原生IPv6]\n", $domain, $ip;
                    }
                }
            } else {
                printf "  %-25s → (无AAAA记录)\n", $domain;
            }
        } else {
            printf "  %-25s → (超时)\n", $domain;
        }
    }
    
    close($sock);
    
    if ($has_dns64 > 0) {
        print "  结论: ✅ 支持DNS64 ($has_dns64 条合成记录)\n";
    } else {
        print "  结论: ❌ 不支持DNS64\n";
    }
    print "\n";
}

print "=" x 70 . "\n";
print "测试完成\n";
print "=" x 70 . "\n";
