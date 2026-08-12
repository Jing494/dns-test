#!/usr/bin/env perl
use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use DNSUtil;   # dns_sockaddr / inet_pton_ipv6 / build_dns_query / parse_dns_response


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
        
        # 解析响应 - A记录（过滤127.0.0.1黑洞=未部署）
        my @ips = parse_dns_response($response, 1);
        my @valid = grep { $_ ne "127.0.0.1" } @ips;
        
        if (@valid) {
            printf "  %-55s -> %s\n", $domain, join(", ", @valid);
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
        my @valid = grep { $_ ne "::1" && $_ ne "0:0:0:0:0:0:0:1" } @ips;  # 过滤IPv6黑洞
        
        if (@valid) {
            printf "  %-55s -> %s (AAAA)\n", $domain, join(", ", @valid);
            $success_aaaa++;
        }
    }
    
    close($sock);
    
    printf "\n成功解析: A记录 %d/%d, AAAA记录 %d/%d\n\n", $success_a, $total, $success_aaaa, $total;
}

print "=" x 80 . "\n";
print "测试完成\n";
print "=" x 80 . "\n";

