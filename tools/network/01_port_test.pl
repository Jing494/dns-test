#!/usr/bin/env perl
use strict;
use warnings;
use Socket qw(:DEFAULT IPPROTO_UDP IPPROTO_TCP);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use DNSUtil;
use POSIX qw(errno_h);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

# ---- CLI 契约：-h/--help 用法输出 + 未知选项拒绝 ----
# 与 examples/*.pl 及 bash 入口保持一致；历史上 - 开头的参数会被当业务参数吞掉
# （如 --help 被当 DNS 地址去解析），这里统一拦截。
sub print_usage {
    print <<"USAGE";
用法: perl 01_port_test.pl [IP 端口 协议] ...
  端口连通性测试（UDP 空包探测 / TCP 非阻塞 connect）
  参数个数必须是 3 的倍数，一组为 IP 端口 协议（协议 tcp/udp）
  例: perl tools/network/01_port_test.pl 223.5.5.5 53 udp
      perl tools/network/01_port_test.pl 223.5.5.5 53 udp 1.1.1.1 443 tcp
  省略参数则用内置默认目标
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

        # 注意：发送 0 字节成功时返回 0（defined 但为假），必须用 defined 判失败
        # （修复前 !$sent 把成功的 0 当失败，UDP 分支永远报"发送失败"）
        if (!defined $sent) {
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


