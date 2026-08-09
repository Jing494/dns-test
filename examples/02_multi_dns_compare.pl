#!/usr/bin/env perl
# 示例2: 多DNS服务器对比测试
# 功能: 同时查询多个DNS服务器，对比解析结果
# 运行: perl 02_multi_dns_compare.pl [DNS1] [DNS2] ... 不传默认4个公共DNS

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);

# 配置: 要测试的DNS服务器
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
        { name => "云南电信DNS 1", address => "222.172.200.68" },
        { name => "云南电信DNS 2", address => "61.166.150.123" },
        { name => "114DNS", address => "114.114.114.114" },
        { name => "阿里云DNS", address => "223.5.5.5" },
        { name => "云南电信DNS v6", address => "240e:52:4800::8888" },
    );
}

# 要测试的域名
my @DOMAINS = ("www.baidu.com", "www.qq.com", "vowifi.189.cn");

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
        
        if ($type == 1 && $rdlength == 4) {
            push @ips, inet_ntoa(substr($response, $offset, 4));
        }
        $offset += $rdlength;
    }
    return @ips;
}

# 主程序
print "=" x 70 . "\n";
print "示例2: 多DNS服务器对比测试\n";
print "测试域名: " . join(", ", @DOMAINS) . "\n";
print "=" x 70 . "\n\n";

my %results;

foreach my $dns (@DNS_SERVERS) {
    printf "%-20s [%s]\n", $dns->{name}, $dns->{address};
    
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
    
    foreach my $domain (@DOMAINS) {
        my $query = build_dns_query($domain, 1);
        my $dest_addr = $dest;
        send($sock, $query, 0, $dest_addr);
        
        my $response;
        my $from = recv($sock, $response, 512, 0);
        
        if ($from) {
            my @ips = parse_dns_response($response, 1);
            if (@ips) {
                $results{$domain}{$dns->{name}} = join(", ", @ips);
                printf "  %-25s → %s\n", $domain, join(", ", @ips);
            } else {
                $results{$domain}{$dns->{name}} = "(无)";
                printf "  %-25s → (无)\n", $domain;
            }
        } else {
            $results{$domain}{$dns->{name}} = "(超时)";
            printf "  %-25s → (超时)\n", $domain;
        }
    }
    
    close($sock);
    print "\n";
}

# 一致性检查
print "=" x 70 . "\n";
print "一致性检查结果:\n";
print "-" x 70 . "\n";

foreach my $domain (@DOMAINS) {
    my %unique;
    foreach my $dns (@DNS_SERVERS) {
        my $result = $results{$domain}{$dns->{name}} || "(无)";
        push @{$unique{$result}}, $dns->{name};
    }
    
    if (scalar(keys %unique) == 1) {
        print "✅ $domain: 所有DNS解析结果一致\n";
    } else {
        print "⚠️  $domain: 解析结果存在差异:\n";
        foreach my $result (keys %unique) {
            printf "    → %s (%s)\n", $result, join(", ", @{$unique{$result}});
        }
    }
}

print "\n" . "=" x 70 . "\n";
print "测试完成\n";
