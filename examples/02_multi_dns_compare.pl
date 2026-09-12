#!/usr/bin/env perl
# 示例2: 多DNS服务器对比测试
# 功能: 同时查询多个DNS服务器，对比解析结果
# 运行: perl 02_multi_dns_compare.pl [DNS1] [DNS2] ... 不传默认4个公共DNS

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
用法: perl 02_multi_dns_compare.pl [DNS1] [DNS2] ...
  默认 运营商DNS×2 + 114 + 阿里 + 运营商v6；支持环境变量 DNS_LIST（逗号分隔）
  例: perl examples/02_multi_dns_compare.pl 223.5.5.5 119.29.29.29
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
        { name => "默认DNS v4-1", address => "222.172.200.68" },
        { name => "默认DNS v4-2", address => "61.166.150.123" },
        { name => "114DNS", address => "114.114.114.114" },
        { name => "阿里云DNS", address => "223.5.5.5" },
        { name => "默认DNS v6", address => "240e:52:4800::8888" },
    );
}

# 要测试的域名
my @DOMAINS = ("www.baidu.com", "www.qq.com", "epdg.epc.mnc011.mcc460.pub.3gppnetwork.org");

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
