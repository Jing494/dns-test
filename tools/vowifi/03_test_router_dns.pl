#!/usr/bin/env perl
# 路由器DNS转发测试
# 功能: 测试内网路由器DNS的解析结果是否与省级DNS（默认示例为运营商DNS）一致
#      一致 → 路由器将DNS请求转发到省级DNS；不一致 → 路由器自建DNS或转发到其他DNS
# 用法: perl 03_test_router_dns.pl [路由器IP1] [路由器IP2] ...
#       不传默认测试 192.168.1.1 / 192.168.2.1（请按自己网络环境传入路由器网关IP）

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use DNSUtil;
$| = 1;  # 立即刷新输出（管道/CI 下防块缓冲导致输出丢失误判）

my $TIMEOUT = 3;

# 被测路由器DNS（-- 前）与省级对比基准（-- 后，逗号分隔）
my @router_dns_list;
my @province_dns;
my $sep_idx = -1;
for (my $i = 0; $i < @ARGV; $i++) {
    if ($ARGV[$i] eq "--") { $sep_idx = $i; last; }
}

if ($sep_idx >= 0) {
    # -- 分隔：前=路由器IP（可多个），后=省级对比基准（逗号分隔）
    @router_dns_list = @ARGV[0 .. $sep_idx - 1];
    my @ref = @ARGV[$sep_idx + 1 .. $#ARGV];
    @province_dns = split(/,/, join(",", @ref));
    print "自定义省级基准(--): " . join(", ", @province_dns) . "\n";
} elsif (@ARGV) {
    @router_dns_list = @ARGV;
    if ($ENV{PROVINCE_DNS}) {
        @province_dns = split(/,/, $ENV{PROVINCE_DNS});
        print "自定义省级基准(环境变量): $ENV{PROVINCE_DNS}\n";
    } else {
        @province_dns = (
            "61.166.150.123",
            "222.172.200.68",
            "240e:52:4800::8888",
            "240e:52:4000::8888",
        );
    }
} else {
    @router_dns_list = ("192.168.1.1", "192.168.2.1");
    @province_dns = (
        "61.166.150.123",
        "222.172.200.68",
        "240e:52:4800::8888",
        "240e:52:4000::8888",
    );
    print "用法: perl 03_test_router_dns.pl [路由器IP1] [路由器IP2] [-- 省级DNS1,省级DNS2]\n";
    print "  例: perl 03_test_router_dns.pl 192.168.1.1              # 默认对比省级DNS（示例为运营商DNS）\n";
    print "  例: perl 03_test_router_dns.pl 192.168.1.1 -- 223.5.5.5  # 自定义省级基准\n";
    print "  也可用环境变量 PROVINCE_DNS=\"223.5.5.5\" 指定基准\n\n";
}

# 测试域名（VoWiFi + 常用网站）
my @domains = (
    "epdg.epc.mnc011.mcc460.pub.3gppnetwork.org",
    "www.baidu.com",
    "www.qq.com",
    "www.taobao.com",
);

print "=" x 70 . "\n";
print "路由器DNS转发测试（对比省级DNS: 默认运营商DNS）\n";
print "=" x 70 . "\n\n";

# ========== 第一步：用省级DNS建立基准 ==========
my %baseline;   # domain => [ip1, ip2, ...]
print "--- 省级基准（默认运营商DNS）解析结果 ---\n";
foreach my $domain (@domains) {
    my %seen;
    $baseline{$domain} = [];  # 初始化，防止自定义基准全空时解引用报错
    foreach my $dns (@province_dns) {
        my $result = query_a($dns, $domain);
        foreach my $ip (split(/,/, $result)) {
            $ip =~ s/^\s+|\s+$//g;
            next if !$ip || $seen{$ip};
            $seen{$ip} = 1;
            push @{$baseline{$domain}}, $ip;
        }
    }
    my $uniq = join(", ", @{$baseline{$domain}});
    printf "  %-50s -> %s\n", $domain, $uniq || "(无记录)";
}
print "\n";

# ========== 第二步：测试各路由器DNS并对比 ==========
foreach my $router_dns (@router_dns_list) {
    printf "路由器DNS: %s\n", $router_dns;
    print "-" x 70 . "\n";
    foreach my $domain (@domains) {
        my $result = query_a($router_dns, $domain);
        my $base = @{$baseline{$domain}} ? join(" ", @{$baseline{$domain}}) : "";
        if (!$result) {
            printf "  ❌ %-44s -> [无响应/超时]\n", $domain;
            next;
        }
        # 取路由器返回的第一个IP与省级基准比对
        my ($first_ip) = split(/,/, $result);
        $first_ip =~ s/^\s+|\s+$//g;
        my $matched = 0;
        foreach my $base_ip (split(/ /, $base)) {
            if ($first_ip eq $base_ip) { $matched = 1; last; }
        }
        if ($matched) {
            printf "  ✅ %-44s -> %s（与省级一致 → 转发到省级DNS）\n", $domain, $result;
        } else {
            printf "  ⚠️  %-44s -> %s（与省级不一致，省级=%s）\n", $domain, $result, $base || "(无记录)";
        }
    }
    print "\n";
}

print "=" x 70 . "\n";
print "测试完成\n";
print "=" x 70 . "\n";

# ========== 工具函数 ==========
# 查询A记录，返回 "ip1, ip2" 或空串（支持v4/v6路由器地址）
sub query_a {
    my ($dns, $domain) = @_;
    my ($dest, $family, $err) = dns_sockaddr($dns, 53);
    return "" unless defined $dest;
    my $sock;
    socket($sock, $family, SOCK_DGRAM, IPPROTO_UDP) or return "";
    setsockopt($sock, SOL_SOCKET, SO_RCVTIMEO, pack("L!L!", $TIMEOUT, 0));
    my $query = build_dns_query($domain, 1);
    my $sent = send($sock, $query, 0, $dest);
    my $result = "";
    if ($sent && $sent == length($query)) {
        my $response;
        my $from = recv($sock, $response, 512, 0);
        if ($from) {
            my @ips = parse_dns_response($response, 1);
            $result = join(", ", @ips);
        }
    }
    close($sock);
    return $result;
}

