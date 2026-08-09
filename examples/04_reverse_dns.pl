#!/usr/bin/env perl
# 示例4: 反向DNS解析 (PTR记录)
# 功能: 将IP地址反向解析为域名
# 运行: perl 04_reverse_dns.pl [DNS地址，不传默认240e:52:4800::8888]

use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);

# 配置: 待反向解析的IP地址（v4/v6 混合）
my @IPS = (
    "8.8.8.8",              # Google DNS
    "114.114.114.114",      # 114 DNS
    "223.5.5.5",            # 阿里云DNS
    "192.0.2.1",       # 云南电信ePDG
    "2001:4860:4860::8888", # Google DNS (IPv6)
    "2400:3200::1",         # 阿里云DNS (IPv6)
);

# 配置: DNS服务器
my $DNS_SERVER = $ARGV[0] || $ENV{DNS_SERVER} || "222.172.200.68";  # 默认云南电信DNS，支持传参/环境变量DNS_SERVER（v4/v6均可）

# IPv6地址转换 

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

# 构建PTR查询
sub build_ptr_query {
    my ($reverse) = @_;
    my $tid = int(rand(65535));
    my $header = pack("n6", $tid, 0x0100, 1, 0, 0, 0);
    my $qname = "";
    foreach my $label (split(/\./, $reverse)) {
        my $len = length($label);
        $len = 63 if ($len > 63);
        $qname .= pack("C", $len) . substr($label, 0, $len);
    }
    $qname .= pack("C", 0);
    my $qtype_class = pack("nn", 12, 1);  # Type PTR = 12
    return $header . $qname . $qtype_class;
}

# 简化版PTR响应解析（仅提取第一个域名）
sub parse_ptr_response_simple {
    my ($response) = @_;
    
    return () if (length($response) < 12);
    
    my ($id, $flags, $qdcount, $ancount) = unpack("n4", substr($response, 0, 12));
    my $rcode = $flags & 0x000F;
    my $qr = ($flags >> 15) & 1;
    return () if (!$qr || $rcode != 0);
    
    my $offset = 12;
    
    # Skip question section
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
    
    # Parse answer section（PTR的rdata才是目标域名，需解析rdata）
    my @names;
    for (my $i = 0; $i < $ancount && $offset < length($response); $i++) {
        # 跳过 owner name（可能含压缩指针）
        my $pos = $offset;
        my $guard = 0;
        while ($pos < length($response) && $guard < 20) {
            my $byte = unpack("C", substr($response, $pos, 1));
            if ($byte == 0) { $pos++; last; }
            if ($byte >= 192) { $pos += 2; last; }
            $pos += $byte + 1;
            $guard++;
        }
        $offset = $pos;
        last if ($offset + 10 > length($response));
        my ($type, $class, $ttl, $rdlength) = unpack("nnNn", substr($response, $offset, 10));
        $offset += 10;
        last if ($offset + $rdlength > length($response));
        
        if ($type == 12) {
            # PTR的rdata是压缩域名，解引用完整解析
            my $rdata_name = "";
            my $rpos = $offset;
            my $rguard = 0;
            while ($rpos < length($response) && $rguard < 20) {
                my $byte = unpack("C", substr($response, $rpos, 1));
                if ($byte == 0) { $rpos++; last; }
                if ($byte >= 192) {
                    # rdata内的压缩指针：跳到目标偏移继续
                    last if ($rpos + 1 >= length($response));
                    my $ptr = (($byte & 0x3F) << 8) | unpack("C", substr($response, $rpos + 1, 1));
                    last if ($ptr >= length($response));
                    $rpos = $ptr;
                    $rguard++;
                    next;
                }
                $rpos++;
                if ($rpos + $byte <= length($response)) {
                    $rdata_name .= substr($response, $rpos, $byte) . "." if $byte > 0;
                    $rpos += $byte;
                }
            }
            $rdata_name =~ s/\.$//;
            push @names, $rdata_name if $rdata_name;
        }
        
        $offset += $rdlength;
    }
    
    return @names;
}

# 构造反向解析域名（v4→in-addr.arpa，v6→ip6.arpa）
sub build_reverse_name {
    my ($ip) = @_;
    if ($ip =~ /:/) {
        my $expanded = expand_ipv6($ip);
        return undef unless defined $expanded;
        my $rev = join(".", reverse split(//, $expanded)) . ".ip6.arpa";
        return $rev;
    } else {
        my @octets = split(/\./, $ip);
        return undef unless @octets == 4;
        return join(".", reverse @octets) . ".in-addr.arpa";
    }
}

# 展开IPv6为32个hex字符
sub expand_ipv6 {
    my ($addr) = @_;
    my $bytes = inet_pton_ipv6($addr);
    return undef unless defined $bytes;
    return join("", map { sprintf("%04x", $_) } unpack("n8", $bytes));
}

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
