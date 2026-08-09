#!/usr/bin/env perl
# 示例1: 基础DNS查询
# 功能: 查询单个域名的A记录和AAAA记录
# 运行: perl 01_dns_query.pl [DNS地址，不传默认240e:52:4800::8888]

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);

# 配置
my $DNS_SERVER = $ARGV[0] || $ENV{DNS_SERVER} || "222.172.200.68";  # 默认云南电信DNS，支持传参/环境变量DNS_SERVER（v4/v6均可）
my @DOMAINS = ("www.baidu.com", "www.qq.com", "www.taobao.com");

# IPv6地址转换函数 

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

# 构建DNS查询包
sub build_dns_query {
    my ($domain, $type) = @_;
    $type ||= 1;  # A记录
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
        } elsif ($type == 28 && $rdlength == 16) {
            my @parts = unpack("n8", substr($response, $offset, 16));
            push @ips, join(":", map { sprintf("%x", $_) } @parts);
        }
        $offset += $rdlength;
    }
    return @ips;
}

# 主程序
print "=" x 60 . "\n";
print "示例1: 基础DNS查询\n";
print "DNS服务器: $DNS_SERVER\n";
print "=" x 60 . "\n\n";

my ($dest, $family, $err) = dns_sockaddr($DNS_SERVER, 53);
if (!defined $dest) {
    print "错误: $err\n";
    exit(1);
}

my $sock;
socket($sock, $family, SOCK_DGRAM, IPPROTO_UDP) or die "创建socket失败: $!\n";
setsockopt($sock, SOL_SOCKET, SO_RCVTIMEO, pack("L!L!", 5, 0));

foreach my $domain (@DOMAINS) {
    print "域名: $domain\n";
    
    # A记录查询
    my $query_a = build_dns_query($domain, 1);
    my $dest_addr = $dest;
    send($sock, $query_a, 0, $dest_addr);
    
    my $response;
    my $from = recv($sock, $response, 512, 0);
    if ($from) {
        my @ips = parse_dns_response($response, 1);
        if (@ips) {
            print "  A记录: " . join(", ", @ips) . "\n";
        } else {
            print "  A记录: (无)\n";
        }
    } else {
        print "  A记录: (超时)\n";
    }
    
    # AAAA记录查询
    my $query_aaaa = build_dns_query($domain, 28);
    $dest_addr = $dest;
    send($sock, $query_aaaa, 0, $dest_addr);
    
    $response = "";
    $from = recv($sock, $response, 512, 0);
    if ($from) {
        my @ips = parse_dns_response($response, 28);
        if (@ips) {
            print "  AAAA记录: " . join(", ", @ips) . "\n";
        } else {
            print "  AAAA记录: (无)\n";
        }
    } else {
        print "  AAAA记录: (超时)\n";
    }
    print "\n";
}

close($sock);
print "=" x 60 . "\n";
print "查询完成\n";
