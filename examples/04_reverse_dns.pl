#!/usr/bin/env perl
# 示例4: 反向DNS解析 (PTR记录)
# 功能: 将IP地址反向解析为域名
# 运行: perl 04_reverse_dns.pl [DNS地址，不传默认240e:52:4800::8888]

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use FindBin;
use lib "$FindBin::Bin/../lib";
use DNSUtil;

# --help/-h 用法提示
if (@ARGV && $ARGV[0] =~ /^(-h|--help)$/) {
    print "用法: perl 04_reverse_dns.pl [DNS地址]\n";
    print "  默认 222.172.200.68（云南电信）；支持环境变量 DNS_SERVER\n";
    exit 0;
}

# 配置: 待反向解析的IP地址（v4/v6 混合，仅公共DNS/私网地址）
my @IPS = (
    "8.8.8.8",              # Google DNS
    "114.114.114.114",      # 114 DNS
    "223.5.5.5",            # 阿里云DNS
    "119.29.29.29",         # 腾讯DNSPod
    "2001:4860:4860::8888", # Google DNS (IPv6)
    "2400:3200::1",         # 阿里云DNS (IPv6)
);

# 配置: DNS服务器
my $DNS_SERVER = $ARGV[0] || $ENV{DNS_SERVER} || "222.172.200.68";  # 默认云南电信DNS，支持传参/环境变量DNS_SERVER（v4/v6均可）

# IPv6地址转换 

# 自动识别IPv4/IPv6地址，返回 (sockaddr, family, error)


# 构建PTR查询

# 简化版PTR响应解析（仅提取第一个域名）

# 构造反向解析域名（v4→in-addr.arpa，v6→ip6.arpa）

# 展开IPv6为32个hex字符

# 主程序
print "=" x 70 . "\n";
print "示例4: 反向DNS解析 (PTR记录)\n";
print "DNS服务器: $DNS_SERVER\n";
print "=" x 70 . "\n\n";

my ($dest, $family, $err) = dns_sockaddr($DNS_SERVER, 53);
if (!defined $dest) {
    print "错误: $err\n";
    exit(1);
}

my $sock;
socket($sock, $family, SOCK_DGRAM, IPPROTO_UDP) or die "创建socket失败: $!\n";
setsockopt($sock, SOL_SOCKET, SO_RCVTIMEO, pack("L!L!", 5, 0));

foreach my $ip (@IPS) {
    # 构造反向解析域名（自动识别IPv4/IPv6）
    my $reverse = build_reverse_name($ip);
    if (!defined $reverse) {
        printf "%-24s (地址格式无效)\n", $ip;
        next;
    }
    
    printf "%-24s (%s)\n", $ip, $reverse;
    
    my $query = build_ptr_query($reverse);
    my $dest_addr = $dest;
    send($sock, $query, 0, $dest_addr);
    
    my $response;
    my $from = recv($sock, $response, 512, 0);
    
    if ($from) {
        my @names = parse_ptr_response_simple($response);
        if (@names) {
            print "  → " . join(", ", @names) . "\n";
        } else {
            print "  → [无PTR记录]\n";
        }
    } else {
        print "  → [超时/无响应]\n";
    }
}

close($sock);
print "\n" . "=" x 70 . "\n";
print "测试完成\n";
