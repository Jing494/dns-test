#!/usr/bin/env perl
# ============================================================================
# 单元测试: lib/DNSUtil.pm 纯函数
# 运行: perl tests/01_dnsutil.t   （或 prove -Ilib tests/）
# 覆盖: dns_sockaddr / inet_pton_ipv6 / build_dns_query / parse_dns_response
# ============================================================================
use strict;
use warnings;
use Test::More;
use Socket qw(AF_INET AF_INET6 inet_aton);
use FindBin;
use lib "$FindBin::Bin/../lib";
use DNSUtil;

# ---------- dns_sockaddr ----------
subtest 'dns_sockaddr IPv4' => sub {
    my ($sa, $fam, $err) = dns_sockaddr("8.8.8.8", 53);
    is($fam, AF_INET, "IPv4 家族=AF_INET");
    ok(defined $sa, "IPv4 sockaddr 已生成");
    is($err, undef, "IPv4 无错误");
};

subtest 'dns_sockaddr 非法 IPv4' => sub {
    my ($sa, $fam, $err) = dns_sockaddr("999.1.1.1", 53);
    ok(!defined $sa, "非法IPv4 sockaddr undef");
    ok(defined $err, "返回错误信息");
};

subtest 'dns_sockaddr IPv6' => sub {
    my ($sa, $fam, $err) = dns_sockaddr("2001:4860:4860::8888", 53);
    is($fam, AF_INET6, "IPv6 家族=AF_INET6");
    ok(defined $sa, "IPv6 sockaddr 已生成");
    is($err, undef, "IPv6 无错误");
};

# ---------- inet_pton_ipv6 ----------
subtest 'inet_pton_ipv6 合法地址' => sub {
    ok(defined inet_pton_ipv6("::1"), "::1");
    ok(defined inet_pton_ipv6("::"), "::");
    ok(defined inet_pton_ipv6("2001:db8::1"), "2001:db8::1 压缩");
    ok(defined inet_pton_ipv6("fe80::1"), "fe80::1");
    ok(defined inet_pton_ipv6("240e:52:4800::8888"), "云南电信IPv6");
    ok(defined inet_pton_ipv6("2001:4860:4860:0:0:0:0:8888"), "全展开无冒号压缩");
};

subtest 'inet_pton_ipv6 非法地址' => sub {
    ok(!defined inet_pton_ipv6("gg::1"), "非法hex拒绝");
    ok(!defined inet_pton_ipv6("1.2.3.4"), "IPv4地址被拒绝(纯v6函数)");
    ok(!defined inet_pton_ipv6("2001:db8:1:2:3:4:5"), "少一段(7段)拒绝");
};

subtest 'inet_pton_ipv6 输出长度' => sub {
    is(length(inet_pton_ipv6("::1")), 16, "::1 展开为16字节");
    is(length(inet_pton_ipv6("240e:52:4800::8888")), 16, "云南电信v6 为16字节");
};

# ---------- build_dns_query ----------
subtest 'build_dns_query 域名编码' => sub {
    my $q = build_dns_query("www.baidu.com", 1);
    # header 12 + qname(含终止0共15) + qtype/class 4 = 31
    is(length($q), 12 + 15 + 4, "A查询总长度正确");
    my $qname = substr($q, 12, 15);
    is($qname, "\x03www\x05baidu\x03com\x00", "qname 标签编码+终止符正确");
    is(substr($q, 26, 1), "\x00", "qname 终止符0");
    my ($qtype, $qclass) = unpack("nn", substr($q, length($q)-4, 4));
    is($qtype, 1, "默认查询类型=A");
    is($qclass, 1, "查询类=IN");
};

subtest 'build_dns_query AAAA类型' => sub {
    my $q = build_dns_query("example.com", 28);
    my ($qtype) = unpack("n", substr($q, length($q)-4, 2));
    is($qtype, 28, "AAAA类型=28");
};

# ---------- parse_dns_response ----------
subtest 'parse_dns_response A记录' => sub {
    my $resp = pack("n6", 0x1234, 0x8180, 1, 1, 0, 0);   # qr=1, rcode=0
    $resp .= "\x03www\x05baidu\x03com\x00";
    $resp .= pack("nn", 1, 1);                            # 问题段
    $resp .= "\xc0\x0c";                                  # 答案名=压缩指针
    $resp .= pack("nnNn", 1, 1, 300, 4);                  # A, IN, ttl, len4
    $resp .= inet_aton("1.2.3.4");
    my @ips = parse_dns_response($resp, 1);
    is(scalar(@ips), 1, "解析出1条A记录");
    is($ips[0], "1.2.3.4", "A记录IP正确");
};

subtest 'parse_dns_response AAAA记录' => sub {
    my $resp = pack("n6", 0x1234, 0x8180, 1, 1, 0, 0);
    $resp .= "\x03www\x05baidu\x03com\x00";
    $resp .= pack("nn", 28, 1);
    $resp .= "\xc0\x0c";
    $resp .= pack("nnNn", 28, 1, 300, 16);
    $resp .= inet_pton_ipv6("2001:db8::1");
    my @ips = parse_dns_response($resp, 28);
    is(scalar(@ips), 1, "解析出1条AAAA记录");
    is($ips[0], "2001:db8:0:0:0:0:0:1", "AAAA记录IPv6正确");
};

subtest 'parse_dns_response NXDOMAIN' => sub {
    my $nx = pack("n6", 1, 0x8183, 1, 0, 0, 0);          # rcode=3 NXDOMAIN
    $nx .= "\x03www\x05baidu\x03com\x00" . pack("nn", 1, 1);
    my @ips = parse_dns_response($nx, 1);
    is(scalar(@ips), 0, "NXDOMAIN 返回空列表");
};

subtest 'parse_dns_response 边界' => sub {
    is(scalar(parse_dns_response("short", 1)), 0, "短于12字节返回空");
    my $no_qr = pack("n6", 1, 0x0100, 1, 0, 0, 0);       # 非响应(qr=0)
    $no_qr .= "\x03www\x05baidu\x03com\x00" . pack("nn", 1, 1);
    is(scalar(parse_dns_response($no_qr, 1)), 0, "qr=0(查询报文)返回空");
};

done_testing();
