#!/usr/bin/env perl
# 路由器DNS转发测试
# 功能: 测试内网路由器DNS的解析结果是否与省级DNS（云南电信）一致
#      一致 → 路由器将DNS请求转发到省级DNS；不一致 → 路由器自建DNS或转发到其他DNS
# 用法: perl 03_test_router_dns.pl [路由器IP1] [路由器IP2] ...
#       不传默认测试 192.168.1.1 / 192.168.2.1（请按自己网络环境传入路由器网关IP）

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);

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
    print "  例: perl 03_test_router_dns.pl 192.168.1.1              # 默认对比云南电信\n";
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
print "路由器DNS转发测试（对比省级DNS: 云南电信）\n";
print "=" x 70 . "\n\n";

# ========== 第一步：用省级DNS建立基准 ==========
my %baseline;   # domain => [ip1, ip2, ...]
print "--- 省级基准（云南电信）解析结果 ---\n";
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
            my $ip = inet_ntoa(substr($response, $offset, 4));
            push @ips, $ip if defined $ip;
        }
        $offset += $rdlength;
    }
    return @ips;
}
