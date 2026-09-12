#!/usr/bin/env perl
use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use DNSUtil;

# ---- CLI 契约：-h/--help 用法输出 + 未知选项拒绝 ----
# 与 examples/*.pl 及 bash 入口保持一致；历史上 - 开头的参数会被当业务参数吞掉
# （如 --help 被当 DNS 地址去解析），这里统一拦截。
sub print_usage {
    print <<"USAGE";
用法: perl 02_vowifi_verify.pl [DNS1] [DNS2] ...
  多 DNS 交叉验证 VoWiFi 解析结果一致性（含 check_ips 历史对比）
  例: perl tools/vowifi/02_vowifi_verify.pl 222.172.200.68 223.5.5.5
  -h, --help  打印本说明
USAGE
}

{
    my $SEP_OK = 0;
    my @unknown;
    for my $a (@ARGV) {
        if ($a =~ /^(-h|--help)$/) { print_usage(); exit 0; }
        next if $SEP_OK && $a eq '--';   # 03: '--' 是"路由器IP / 省级基准"分隔符，不算选项
        push @unknown, $a if $a =~ /^-/;
    }
    if (@unknown) {
        print STDERR "❌ 未知选项: $unknown[0]（可用 --help 查看用法）\n";
        exit 1;
    }
}

$| = 1;  # 立即刷新输出（管道/CI 下防块缓冲导致输出丢失误判）

my $TIMEOUT = 5;

# 默认DNS（示例为运营商DNS）
my @dns_servers;
if (@ARGV) {
    foreach my $addr (@ARGV) {
        push @dns_servers, { name => "自定义DNS", address => $addr };
    }
} else {
    @dns_servers = (
        { name => "默认DNS v6", address => "240e:52:4800::8888" },
        { name => "默认DNS v4", address => "222.172.200.68" },
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
            my $status = check_ips($domain, \@valid, $previous_ips{$domain});
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

