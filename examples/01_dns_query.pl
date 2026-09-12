#!/usr/bin/env perl
# 示例1: 基础DNS查询
# 功能: 查询单个域名的A记录和AAAA记录
# 运行: perl 01_dns_query.pl [DNS地址，不传默认240e:52:4800::8888]

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use FindBin;
use lib "$FindBin::Bin/../lib";
use DNSUtil;

# ---- CLI 契约：-h/--help 用法输出 + 未知选项拒绝 ----
# 扫描全部参数而非只看首个：保证 --help/-h 出现在任意位置都生效；
# 任何 - 开头的未知选项被明确拒绝（历史实现只查 $ARGV[0]，
# 于是 `... 8.8.8.8 --help` 会把 --help 当成第 2 个 DNS 地址）。
sub print_usage {
    print <<"USAGE";
用法: perl 01_dns_query.pl [DNS地址]
  默认 222.172.200.68（示例）；支持环境变量 DNS_SERVER
  例: perl examples/01_dns_query.pl 223.5.5.5
  -h, --help  打印本说明
USAGE
}

{
    my @unknown;
    for my $a (@ARGV) {
        if ($a =~ /^(-h|--help)$/) { print_usage(); exit 0; }
        push @unknown, $a if $a =~ /^-/;
    }
    if (@unknown) {
        print STDERR "❌ 未知选项: $unknown[0]（可用 --help 查看用法）\n";
        exit 1;
    }
}

# 配置
my $DNS_SERVER = $ARGV[0] || $ENV{DNS_SERVER} || "222.172.200.68";  # 默认运营商DNS，支持传参/环境变量DNS_SERVER（v4/v6均可）
my @DOMAINS = ("www.baidu.com", "www.qq.com", "www.taobao.com");

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
