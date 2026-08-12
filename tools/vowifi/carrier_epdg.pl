#!/usr/bin/env perl
# 运营商 VoWiFi ePDG 部署检测
# 功能: 检测各大运营商（电信/移动/联通/广电）的 ePDG 域名解析情况，
#       判断该运营商在当前省份是否部署了 VoWiFi 服务
# 用法:
#   perl carrier_epdg.pl                    # 交互模式：选运营商 + 选DNS来源
#   perl carrier_epdg.pl all                # 全部运营商，默认云南电信DNS
#   perl carrier_epdg.pl ct                 # 只测电信
#   perl carrier_epdg.pl cmcc 223.5.5.5     # 移动，自定义DNS
#   perl carrier_epdg.pl cucc router        # 联通，家宽路由器DNS
#   perl carrier_epdg.pl ct 222.172.200.68,61.166.150.123  # 电信，多DNS
# 运营商: ct(电信) / cmcc(移动) / cucc(联通) / cbn(广电) / all(全部)
# 说明: 仅反映DNS解析/部署情况，实际可用性需自测（需终端支持VoWiFi + 运营商开通）

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use DNSUtil;

my $TIMEOUT = 3;

# ========== 运营商 ePDG 域名映射（MCC 460 中国，MNC归属经ITU/维基核实） ==========
# 电信 MNC: 11(4G/5G主用,实测部署ePDG) / 03,05(CDMA历史)
# 移动 MNC: 00 / 02 / 07
# 联通 MNC: 01 / 06 / 09
# 广电 MNC: 15
my %carriers = (
    ct => {
        name  => "中国电信",
        short => "CT",
        domains => [
            "epdg.epc.mnc011.mcc460.pub.3gppnetwork.org",  # 实测有部署
            "epdg.epc.mnc003.mcc460.pub.3gppnetwork.org",
        ],
    },
    cmcc => {
        name  => "中国移动",
        short => "CMCC",
        domains => [
            "epdg.epc.mnc000.mcc460.pub.3gppnetwork.org",
            "epdg.epc.mnc002.mcc460.pub.3gppnetwork.org",
            "epdg.epc.mnc007.mcc460.pub.3gppnetwork.org",
        ],
    },
    cucc => {
        name  => "中国联通",
        short => "CUCC",
        domains => [
            "epdg.epc.mnc001.mcc460.pub.3gppnetwork.org",
            "epdg.epc.mnc006.mcc460.pub.3gppnetwork.org",
            "epdg.epc.mnc009.mcc460.pub.3gppnetwork.org",
        ],
    },
    cbn => {
        name  => "中国广电",
        short => "CBN",
        domains => [
            "epdg.epc.mnc015.mcc460.pub.3gppnetwork.org",
        ],
    },
);

# 默认 DNS（云南电信，可用环境变量 PROVINCE_DNS 覆盖——用你所在省份的省级DNS测当地ePDG部署）
my @default_dns;
if ($ENV{PROVINCE_DNS}) {
    @default_dns = split(/,/, $ENV{PROVINCE_DNS});
    print "自定义省级DNS(环境变量): $ENV{PROVINCE_DNS}\n";
} else {
    @default_dns = ("222.172.200.68", "61.166.150.123", "240e:52:4800::8888", "240e:52:4000::8888");
}
# 家宽路由器 DNS
my @router_dns = ("192.168.1.1", "192.168.2.1");

# ========== 参数解析 ==========
my ($carrier_arg, $dns_arg) = @ARGV;

# 交互模式（无参数时询问）
if (!defined $carrier_arg) {
    print "=" x 70 . "\n";
    print "运营商 VoWiFi ePDG 部署检测\n";
    print "=" x 70 . "\n\n";
    print "请选择运营商:\n";
    print "  1. 中国电信 (CT)\n";
    print "  2. 中国移动 (CMCC)\n";
    print "  3. 中国联通 (CUCC)\n";
    print "  4. 中国广电 (CBN)\n";
    print "  5. 全部\n";
    print "请输入选项(1-5): ";
    my $sel = <STDIN>;
    chomp $sel;
    my %sel_map = (1 => "ct", 2 => "cmcc", 3 => "cucc", 4 => "cbn", 5 => "all");
    $carrier_arg = $sel_map{$sel} || "all";
    print "\n请选择DNS来源:\n";
    print "  1. 默认云南电信（省级DNS）\n";
    print "  2. 家宽路由器 (192.168.1.1/192.168.2.1)\n";
    print "  3. 自定义（输入DNS，多个用逗号分隔）\n";
    print "请输入选项(1-3): ";
    my $dsel = <STDIN>;
    chomp $dsel;
    if ($dsel == 2) {
        $dns_arg = "router";
    } elsif ($dsel == 3) {
        print "请输入DNS地址: ";
        $dns_arg = <STDIN>;
        chomp $dns_arg;
    }
}

# 解析 DNS 列表
my @dns_list;
if (defined $dns_arg) {
    if ($dns_arg eq "router") {
        @dns_list = @router_dns;
    } else {
        @dns_list = split(/,/, $dns_arg);
    }
} else {
    @dns_list = @default_dns;
}

# 解析运营商列表
my @carrier_keys;
if ($carrier_arg eq "all") {
    @carrier_keys = sort keys %carriers;
} elsif (exists $carriers{$carrier_arg}) {
    @carrier_keys = ($carrier_arg);
} else {
    print "❌ 未知运营商: $carrier_arg (可选: ct/cmcc/cucc/cbn/all)\n";
    exit 1;
}

print "=" x 70 . "\n";
print "运营商 VoWiFi ePDG 部署检测\n";
print "=" x 70 . "\n\n";
print "检测DNS: " . join(", ", @dns_list) . "\n\n";

my $deployed_total = 0;
my $domain_total = 0;

foreach my $ck (@carrier_keys) {
    my $carrier = $carriers{$ck};
    print "-" x 70 . "\n";
    printf "运营商: %s (%s) — %d 个ePDG域名\n", $carrier->{name}, $carrier->{short}, scalar(@{$carrier->{domains}});
    print "-" x 70 . "\n";
    my $found = 0;
    foreach my $domain (@{$carrier->{domains}}) {
        $domain_total++;
        my $ips = query_all($domain);
        if ($ips) {
            $found++;
            $deployed_total++;
            printf "  ✅ %-58s → %s [已部署]\n", $domain, $ips;
        } else {
            printf "  ⚠️  %-58s → 无记录 [未部署]\n", $domain;
        }
    }
    if ($found > 0) {
        printf "  结论: %s ePDG 已部署（%d/%d 域名可解析）\n", $carrier->{name}, $found, scalar(@{$carrier->{domains}});
    } else {
        printf "  结论: %s ePDG 未部署（%d/%d 域名无记录）\n", $carrier->{name}, 0, scalar(@{$carrier->{domains}});
    }
    print "\n";
}

print "=" x 70 . "\n";
printf "汇总: %d/%d 域名可解析\n", $deployed_total, $domain_total;
print "=" x 70 . "\n";
print "⚠️  免责声明: 本检测仅反映 DNS 解析/部署情况，\n";
print "    实际可用性需自行测试（需终端支持VoWiFi、运营商开通、网络环境允许）。\n";
print "    未部署 = 无解析记录，不代表将来不部署；部分域名可能仅内网DNS可解析。\n";
print "    运营商可能使用非公开域名，标准3gppnetwork域名无记录 ≠ 绝对未部署。\n";
print "=" x 70 . "\n";

# ========== 工具函数 ==========
# 用所有DNS查询A记录，返回 "ip1, ip2"（合并去重）或空
sub query_all {
    my ($domain) = @_;
    my %seen;
    my @ips;
    foreach my $dns (@dns_list) {
        my $r = query_a($dns, $domain);
        foreach my $ip (split(/,/, $r)) {
            $ip =~ s/^\s+|\s+$//g;
            next if !$ip || $ip eq "127.0.0.1" || $seen{$ip};  # 127.0.0.1=运营商黑洞(未部署)
            $seen{$ip} = 1;
            push @ips, $ip;
        }
    }
    return join(", ", @ips);
}

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




