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

# ---------- check_ips ----------
subtest 'check_ips IP一致性' => sub {
    is(check_ips("x.com", ["1.1.1.1"], ["1.1.1.1"]), "[✓ 与之前一致]", "无变化→一致");
    is(check_ips("x.com", ["1.1.1.1", "2.2.2.2"], ["1.1.1.1"]), "[⚠️ 新增IP: 2.2.2.2]", "新增IP提示");
    is(check_ips("x.com", ["2.2.2.2"], ["1.1.1.1"]), "[⚠️ 新增IP: 2.2.2.2 | 消失IP: 1.1.1.1]", "IP变化提示(新增+消失)");
    is(check_ips("x.com", ["1.1.1.1"], ["1.1.1.1", "2.2.2.2"]), "[⚠️ 消失IP: 2.2.2.2]", "消失IP提示");
    is(check_ips("x.com", ["1.1.1.1"], undef), "", "无历史返回空");
};

# ---------- PTR 相关 ----------
subtest 'build_reverse_name 反向域名' => sub {
    is(build_reverse_name("8.8.8.8"), "8.8.8.8.in-addr.arpa", "IPv4 反向名");
    is(build_reverse_name("1.2.3.4"), "4.3.2.1.in-addr.arpa", "IPv4 反向名(倒序)");
    ok(defined build_reverse_name("240e:52:4800::8888"), "IPv6 反向名生成");
    like(build_reverse_name("::1"), qr/^1(\.0){31}\.ip6\.arpa$/, "::1 反向名(32段)");
    is(build_reverse_name("1.2.3"), undef, "非法IPv4段数返回undef");
};

subtest 'expand_ipv6' => sub {
    is(expand_ipv6("::1"), "00000000000000000000000000000001", "::1 展开32hex");
    is(length(expand_ipv6("240e:52:4800::8888")), 32, "云南电信v6 32字符");
    is(expand_ipv6("gg::1"), undef, "非法hex返回undef");
};

subtest 'build_ptr_query 编码' => sub {
    my $q = build_ptr_query("8.8.8.8.in-addr.arpa");
    my ($qtype) = unpack("n", substr($q, length($q)-4, 2));
    is($qtype, 12, "PTR类型=12");
    like(substr($q, 12, length($q)-16), qr/^\x01\x38/, "反向域名编码(1,8,8,8...)");
};

subtest 'parse_ptr_response_simple' => sub {
    # 构造 PTR 响应: 8.8.8.8.in-addr.arpa → dns.google
    my $resp = pack("n6", 0x1234, 0x8180, 1, 1, 0, 0);
    $resp .= "\x01\x38\x01\x38\x01\x38\x01\x38\x07in-addr\x04arpa\x00";
    $resp .= pack("nn", 12, 1);
    $resp .= "\xc0\x0c";                                  # owner 压缩指针
    $resp .= pack("nnNn", 12, 1, 300, 16);                # PTR, rdlength=16
    # rdata 域名（label 长度必须精确：dns=3/google=6/com=3；\x03 后跟 hex 字符需拆开写）
    $resp .= "\x03dns\x06google" . "\x03" . "com\x00";
    my @names = parse_ptr_response_simple($resp);
    is(scalar(@names), 1, "解析出1个PTR名");
    is($names[0], "dns.google.com", "PTR目标域名正确");
};

# ---------- 畸形包防崩（E） ----------
subtest 'parse_dns_response 畸形包防崩' => sub {
    # 随机/截断/异常输入不应崩溃（返回空列表即可）
    my @weird = (
        "", "x", "\x00" x 12, "\xff" x 200,
        pack("n6", 1, 0x8180, 1, 1, 0, 0) . "\xff" x 100,   # 声明有答案但数据畸形
        "\x00\x01\x02\x03" x 10,
        join("", map { chr(int(rand(256))) } 1 .. 300),      # 随机字节
        join("", map { chr(int(rand(256))) } 1 .. 300),      # 再来一包随机
    );
    for my $pkt (@weird) {
        my @r = eval { parse_dns_response($pkt, 1) };
        ok(!$@, "畸形包不崩溃 (len=" . length($pkt) . ")") or diag $@;
    }
    # 定向：64-191 保留位标签（P2修复）——不应被当普通长度跳变，解析受限且不崩
    my $mal = pack("n6", 1, 0x8180, 1, 1, 0, 0) . chr(100) . "x" . "\x00" . pack("nn", 1, 1);
    $mal .= chr(100) . "x" . "\x00" . pack("nnNn", 1, 1, 0, 4) . pack("C4", 9, 9, 9, 9);
    my @rm = eval { parse_dns_response($mal, 1) };
    ok(!$@, "64-191畸形标签不崩溃") or diag $@;
    ok(@rm <= 1, "64-191畸形标签结果受限(<=1条)");
};

done_testing();
