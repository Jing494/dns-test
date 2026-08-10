#!/usr/bin/env perl
use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use POSIX qw(errno_h);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

my $TIMEOUT = 5;

# 测试目标
my @targets;
if (@ARGV) {
    # 传入参数格式：IP 端口 协议(tcp/udp)，必须是3的倍数
    if (@ARGV % 3 != 0) {
        print "警告: 参数个数 ${\scalar @ARGV} 不是3的倍数（应为 IP 端口 协议 的整数倍），多余参数将被忽略\n";
    }
    for (my $i=0; $i+2 < @ARGV; $i+=3) {
        push @targets, {
            ip => $ARGV[$i],
            port => $ARGV[$i+1],
            proto => $ARGV[$i+2] || "udp",
            name => "自定义测试 $ARGV[$i]:$ARGV[$i+1]/$ARGV[$i+2]"
        };
    }
} else {
    # 默认目标：仅使用公共DNS/私网地址（安全，不含运营商内部IP）
    @targets = (
        { ip => "223.5.5.5", port => 53, proto => "udp", name => "阿里DNS UDP 53" },
        { ip => "119.29.29.29", port => 53, proto => "udp", name => "腾讯DNS UDP 53" },
        { ip => "8.8.8.8", port => 53, proto => "udp", name => "Google DNS UDP 53" },
        { ip => "223.5.5.5", port => 53, proto => "tcp", name => "阿里DNS TCP 53" },
        { ip => "192.168.1.1", port => 53, proto => "udp", name => "私网路由器 UDP 53" },
    );
}

print "=" x 70 . "\n";
print "ePDG服务器端口连通性测试\n";
print "=" x 70 . "\n\n";

foreach my $t (@targets) {
    printf "测试: %-30s %s://%s:%d\n", $t->{name}, $t->{proto}, $t->{ip}, $t->{port};
    
    # v4/v6 自动识别（复用dns_sockaddr双栈）
    my ($dest_addr, $family, $err) = dns_sockaddr($t->{ip}, $t->{port});
    if (!defined $dest_addr) {
        print "  [错误] 地址格式无效: $err\n\n";
        next;
    }
    
    my $sock;
    if ($t->{proto} eq "udp") {
        # UDP测试
        socket($sock, $family, SOCK_DGRAM, IPPROTO_UDP) or do {
            print "  [错误] 无法创建socket: $!\n\n";
            next;
        };
        
        # 设置接收超时，避免UDP无响应时永久阻塞
        setsockopt($sock, SOL_SOCKET, SO_RCVTIMEO, pack("L!L!", $TIMEOUT, 0));
        
        # 发送一个空的UDP包
        my $sent = send($sock, "", 0, $dest_addr);
        
        if (!$sent) {
            print "  UDP: ❌ 发送失败 - $!\n\n";
            close($sock);
            next;
        }
        
        # 等待响应
        my $response;
        my $from = recv($sock, $response, 512, 0);
        
        if ($from) {
            print "  UDP: ✅ 收到响应 (" . length($response) . " bytes)\n";
        } else {
            print "  UDP: ⚠️  无响应/超时\n";
            print "        （空UDP包探测：多数UDP服务对空包不回包，无法区分开放/过滤）\n";
            print "        （如需确认，请用真实协议流量测试，如IKE/IPsec协商）\n";
        }
    } else {
        # TCP测试（非阻塞connect，避免黑洞IP导致长时间卡死）
        socket($sock, $family, SOCK_STREAM, IPPROTO_TCP) or do {
            print "  [错误] 无法创建socket: $!\n\n";
            next;
        };
        
        # 设置为非阻塞模式，connect立即返回，用select等待结果
        my $flags = fcntl($sock, F_GETFL, 0);
        fcntl($sock, F_SETFL, $flags | O_NONBLOCK);
        
        my $result = connect($sock, $dest_addr);
        
        if ($result) {
            print "  TCP: ✅ 连接成功（端口开放）\n";
        } else {
            if ($! == EINPROGRESS || $! == EWOULDBLOCK) {
                # 等待连接完成
                my $rin = "";
                vec($rin, fileno($sock), 1) = 1;
                my $n = select(my $rout = $rin, undef, undef, $TIMEOUT);
                if ($n > 0) {
                    my $err = getsockopt($sock, SOL_SOCKET, SO_ERROR);
                    if (defined $err && unpack("I", $err) == 0) {
                        print "  TCP: ✅ 连接成功（端口开放）\n";
                    } else {
                        print "  TCP: ❌ 连接失败（端口关闭或过滤）\n";
                    }
                } else {
                    print "  TCP: ❌ 连接超时（端口可能被过滤）\n";
                }
            } elsif ($! == ECONNREFUSED) {
                print "  TCP: ❌ 连接被拒绝（端口关闭）\n";
            } else {
                print "  TCP: ❌ 连接失败 - $!\n";
            }
        }
    }
    
    close($sock);
    print "\n";
}

print "=" x 70 . "\n";
print "测试完成\n";
print "=" x 70 . "\n";

# ========== v4/v6 双栈工具函数 ==========
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
