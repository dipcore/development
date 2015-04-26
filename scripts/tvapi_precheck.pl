#!/usr/bin/perl
use strict;

=readme
这是一个检查错误的脚本，脚本提供的信息包括：
1. 签名有误，将扰乱native机制，而编译器不检查的部分，yellow信息标出
2. 遗漏问题，java，jni和.h三者不匹配的，blue信息标出
3. java和cpp的命名不一致问题，可能是笔误，也可能就是无法保持一致，purple信息标出
4. jni部分声明但未定义，cyan信息标出
还有black和green信息没用到，可供提供进一步的信息

这个脚本正常工作需要遵循一些规则，弱规则我尽量进行了兼容，如果还有没照顾到的，请联系我修改，或者自己参考脚本注释修改
强规则是脚本正常工作所必须的，以下列出的是目前为止发现的对脚本工作所必须的规则：
1. jni的文件的函数定义要求下面的格式：
[static] void com_mstar_android_tvapi_FUNCTION[_ARGS]
(args) {
    xxxx
}
static是可选的弱规则，小写部分是必须要一致的
FUNCTION必须与.h的函数名一致，起码字母要全部一样，不区分大小写，function,Function，FuncTion都是接受的
脚本将处理重载，因而如果重载请加上_ARGS来定义另外的函数，下划线是必须的，否则没办法区分call和callback
当然如果.h里面同时定义了call，back，call_back，那就呵呵了
2. 如果jimmy还在因为格式无情地拒绝你，这里有一个自动化的方法：
$> cat >jimmy.noreject <<EOF
--style=java
--pad-oper
--pad-header
--unpad-paren
--convert-tabs
--suffix=.fmtbk
--indent-switches
--indent-preprocessor
--add-brackets
--align-pointer=name
<<EOF
$> find code_path -name "*.cpp" -o -name "*.java" | xargs -i astyle --options=jimmy.noreject {}
上面那个是jimmy官方认可的style，不work请找jimmy
3. 脚本会处理重载，重载的意思是说，java那边和cpp这边的一一对应
如果java那边多个对应cpp一个，就会报.h里面的函数在jni没找到，这个应该是不合理的，理应找到并fix它
如果cpp这边多个对应java那边一个，也是报.h的函数在jni没找到，这个则属于遗漏
4. .h那边因为规则散漫，所以出问题也最多，目前的已知问题是宏隔开的多个定义会被识别为not found jni
5. jni这边的PostEvent也算很混乱的，大小写，下划线，各种混乱
目前要求PostEvent_NAME这样的名称起码要包含在fields里面，另外假设PostEvent是没有重载的，抱歉
初始化请放在native_init里面
对接检查将以native_init里面的为准，字符串检查java那边，field则检查jni这边
6. 报not implement的原因是：
对于jni函数，脚本试图直接将.h那边找到的函数名去搜函数体，如果找到则认为实现了，但是如果是你简单放了进去，又注释掉，那这个就查不到了
对于PostEvent函数则试图将PostEvent的name去搜函数体，因为要求fields包含name，所以如果搜到就认为还是做了处理的，当然注释掉也是差不到的
7. 报名称不对应的原因，主要是为了排查手写出错的问题，比如说{"enable1", "()V", enable2}，打印出来就能排查粗心错误
这也是粗略检查，比如这样的{"enable", "()V", enable234}这样就查不出来，如果重载，请加下划线enable_234

这一节是原理，供希望修改脚本的人参考
1. 脚本核心是dir_entry，这个负责迭代指定目录内的所有项，这里是迭代jni.cpp，然后再分别根据文件名规则找到.h和.java，所以文件名规则一定是强规则
2. dir_entry里面负责分别调用jni，cpp，java的解析函数
3. jni解析函数扫2遍，第一遍是获取元数据，也就是JNIListener和jni_table，第二遍则检查元数据对应的函数
PostEvent检查形如JNIListener::PostEvent_的字眼，作为定义，native_init攫取与jni_table类似的结构，其余的以com_mstar_android_tvapi_起头的字眼则对照jni_table
4. jni找到的表分别与.h和.java进行对照
5. 对照的核心价值主要在于检查那些字符串对接的部分，即编译器检查不出来，需要在运行时检查的部分
6. 如果脚本出错，首先就查看分布在各处的正则表达式，多半都是正则表达式遇上了无法匹配的规则导致的，复杂的正则表达式有规则注释，供参考
7. next if的地方都是潜规则

如果有任何问题，请联系colin.hu@mstarsemi.com或者自己修改或者联系jimmy
=cut

sub log_black {
    print "\033[1;30m@_\033[0m\n";
}

sub log_red {
    print "\033[1;31m@_\033[0m\n";
}

sub log_green {
    print "\033[1;32m@_\033[0m\n";
}

sub log_yellow {
    print "\033[1;33m@_\033[0m\n";
}

sub log_blue {
    print "\033[1;34m@_\033[0m\n";
}

sub log_purple {
    print "\033[1;35m@_\033[0m\n";
}

sub log_cyan {
    print "\033[1;36m@_\033[0m\n";
}

sub log_default {
    print "@_\n";
}

sub dir_foreach {
    my ($curdir, $callback) = @_;
    if(not -d $curdir){
        print "$curdir not a directory";
        return;
    }
#   print "\033[0;36menter $curdir\n";
    my $CDIR;
    opendir($CDIR, "$curdir") or die "failed to opendir $curdir\n";
    while(my $edir = readdir($CDIR)){
       my $fullpath = "$curdir/$edir";
       if($edir eq "." or $edir eq ".."){
       }
       elsif(-T $fullpath){
           &$callback("$fullpath");
       }
       elsif(-d $fullpath){
           dir_foreach("$fullpath", $callback);
       }
       elsif(-l $fullpath){
           #print "skip symbol link file\n";
       }
       else{
           #print "file $fullpath can't support\n";
       }
    }
    closedir($CDIR);
#   print "\033[0;36mleave $curdir\n";
}

sub dir_entry {
    my $dir = shift;
    my $callback = shift;
    my $CDIR;
    opendir($CDIR, "$dir") or warn "failed to opendir $dir\n";
    while(my $ent = readdir($CDIR)){
        my $fullpath = "$dir/$ent";
        &$callback($fullpath) unless grep {/$ent/} @_;
    }
    closedir($CDIR);
}

unless (defined $ENV{ANDROID_BUILD_TOP}) {
    log_cyan "plz source build/envsetup.sh; lunch";
    exit;
}

my $java_tvapi_path = "$ENV{ANDROID_BUILD_TOP}/device/mstar/common/libraries/tvapi/java";
my $jni_tvapi_path = "$ENV{ANDROID_BUILD_TOP}/device/mstar/common/libraries/tvapi/jni";
my $inc_tvapi_path = "$ENV{ANDROID_BUILD_TOP}/device/mstar/".($ENV{TARGET_PRODUCT} =~ /[^_]+_([^-]*)/)[0]."/libraries/tvapi/include";

my @parse_table;

sub jni_signature_check {
    my ($jtype, $sig) = @_;
    return 1 if $jtype eq 'jobject' and $sig =~ /^(\[?L|\[(I|Z|S|B|C|J|F|D))/
        or $jtype eq 'jstring' and $sig eq 'Ljava/lang/String;'
        or $jtype eq 'void' and $sig eq 'V'
        or $jtype eq 'jint' and $sig eq 'I'
        or $jtype eq 'jsize' and $sig eq 'I'
        or $jtype eq 'jboolean' and $sig eq 'Z'
        or $jtype eq 'jshort' and $sig eq 'S'
        or $jtype eq 'jbyte' and $sig eq 'B'
        or $jtype eq 'jchar' and $sig eq 'C'
        or $jtype eq 'jlong' and $sig eq 'J'
        or $jtype eq 'jfloat' and $sig eq 'F'
        or $jtype eq 'jdouble' and $sig eq 'D'
        or $jtype eq 'jintArray' and $sig eq '[I'
        or $jtype eq 'jbooleanArray' and $sig eq '[Z'
        or $jtype eq 'jshortArray' and $sig eq '[S'
        or $jtype eq 'jbyteArray' and $sig eq '[B'
        or $jtype eq 'jcharArray' and $sig eq '[C'
        or $jtype eq 'jlongArray' and $sig eq '[J'
        or $jtype eq 'jfloatArray' and $sig eq '[F'
        or $jtype eq 'jdoubleArray' and $sig eq '[D';
    return 0;
}

sub jni_signature_argcheck {
    my ($args, $sig) = @_;
    $args =~ s/\((.*)\)/\1/;
    my @args = split ',', $args;
    shift @args;
    shift @args;
    for (@args) {
        my ($earg) = /(\w+)/;
        my ($esig) = $sig =~ /(\[?(V|I|Z|S|B|J|F|D|L[^;]*;))/;
        $sig = $';
        return 0 unless jni_signature_check($earg, $esig);
    }
    return 1 if not $sig;
    return 0;
}

sub java_signature_check {
    my ($type, $sig) = @_;
    if($type =~ /\s*\[]/){
        $type = $`;
        return 0 unless $sig =~ /^\[/;
        $sig = $';
    }
    return 1 if $type eq 'void' and $sig eq 'V'
        or $type eq 'int' and $sig eq 'I'
        or $type eq 'boolean' and $sig eq 'Z'
        or $type eq 'short' and $sig eq 'S'
        or $type eq 'byte' and $sig eq 'B'
        or $type eq 'char' and $sig eq 'C'
        or $type eq 'long' and $sig eq 'J'
        or $type eq 'float' and $sig eq 'F'
        or $type eq 'double' and $sig eq 'D'
        or $sig =~ $type;
    return 0;
}

sub java_signature_argcheck {
    my ($args, $sig) = @_;
    $args =~ s/\((.*)\)/\1/;
    my @args = split ',', $args;
    for (@args) {
        my ($earg) = /(\w+(?:\s*\[])?)/;
        my ($esig) = $sig =~ /(\[?(I|Z|S|B|J|F|D|L[^;]*;))/;
        $sig = $';
        return 0 unless java_signature_check($earg, $esig);
    }
    return 1 if not $sig;
    return 0;
}

sub function_block_catch {
    my ($FD) = @_;
    my $string = qr/("((?:[^\\"]|(?:\\"))*?)")/;
    #这个是匹配注释的规则，主要防止注释内部出现的}导致匹配出错，这里还假设字符串是单行的
    my $brace = 1;
    #jimmy要求{跟在function后面，所以假设第一个{是已经存在的，如果出现匹配出错，astyle --style=java一下可以缓解应该就是这里有问题了
    my $find_all_char = sub {
        my ($line, $charexp) = @_;
        my ($counter, $iter) = (0, 0);
        while($iter = ($line =~ /$charexp/)){
            $counter += $iter;
            $line = $';
        }
        return $counter;
    };
    my $block;
    while(<$FD>){
        my $line = $_;
        $block .= $_;
        while($line =~ /$string/){
            $line = $`.$';
        }
        if(/\/\/.*/){
            #单行注释
            $line = $`;
        }
        if(/\/\*/){
            #多行注释
            $line = "$`";
            while(<$FD>){
                $block .= $_;
                if(/\*\//){
                    $line .= " $'";
                    last;
                }
            }
        }
        chomp($line);
        $brace += &$find_all_char($line, qr/{/);
        $brace -= &$find_all_char($line, qr/}/);
        last if $brace eq 0;
    }
    return $block;
}

sub jni_api_parser {
    my ($file, $key) = @_;
    my $FD;
    my %cpp_table;
    my %java_table;
    my %event_table;
    my @functions;
    open $FD, $file or warn "can't open $file $!\n";
    my ($file2) = $file =~ /.*\/(.*)/;
    while(<$FD>){
        if(/^class\s*JNIMSrvListener\b/){
            while(<$FD>){
                last if /^};/;
                if(/^public:/){
                    while(<$FD>){
                        last if /^private:/;
                        next if /JNIMSrvListener|notify|Template|SnServiceDeadth/;
                        $event_table{$1} = "" if /^\s+\w+\s+(\w+)/;
                    }
                }
            }
        }
        if(/^static\s*JNINativeMethod\b/){
            while(<$FD>){
                last if /^};/;
                chomp;
                my ($java, $sig, $cpp) = /^\s+{"(\w+)",\s*"([^"]*)"\s*,[^)]*\)\s*(\w+)}/;
                #                           {"java_method", "sig",  (void *) cpp_function}
#                log_red "jni: $java, $sig, $cpp\n";
                if($java and $sig and $cpp){
                    $java_table{$java}{$sig} = $cpp;
                    $cpp_table{$cpp} = [$sig];
                    $java =~ /\b(?:native)?(\w+)/;
                    log_purple "$file2, <$java and $cpp> differ???" unless $cpp =~ /$1/i;
                }else{
                    log_red "<$file2>can't match jni line:[$_]\n";
                }
            }
            last;
        }
    }
    close $FD;

    open $FD, $file or warn "can't open $file $!\n";
    my @event_dup = keys %event_table;
    my @event_dup2 = keys %event_table;
    while(<$FD>){
        if(/JNIMSrvListener::(PostEvent_(\w+))/){
            #找到PostEvent的定义
            my ($ename, $keyname) = ($1, $2);
            next if $ename =~ /template|SnServiceDeadth/i;
            for my $i (0..@event_dup-1){
                if($event_dup[$i] eq $ename){
                    splice @event_dup, $i, 1;
                    last;
                }
            }
            if(/}/){
                log_cyan "$file2: $ename is empty.";
            }else{
                my $block = function_block_catch($FD);
                unless ($block =~ /$2/si){
                    log_cyan "$file2: $ename defined but not implement.{";
                    log_cyan $block;
                }
            }
        }
        my ($rval, $cpp) = /^(?:static\s+)?(\w+)\s+(com_mstar_android_tvapi_\w+)/;
        #                      [static]    ret_type com_mstar_android_tvapi_function_args
        #                     可选的static，但是如果真对symbols管理严谨的话，用namespace {}是更好选择
        if($cpp){
            my $flag = 0;
            my $args = "\n";
            while(<$FD>){
                $args =~ s/\n/$_/;
                last if /\{/;
            }
            chomp($args);

            if($cpp =~ /native_init$/){
                my @block = split "\n", function_block_catch($FD);
                for my $line (@block){
                    if($line =~ /^\s*fields\.(\w+)\s*=\s*env->GetStaticMethodID\(clazz,\s*\"(\w+)\"\s*,\s*\"([^\"]+)\"/){
                        #            fields.post_event_KEYNAME = env->GetStaticMethodID(clazz, "PostEvent_java", "(arg)rval"
                        my ($efield, $emethod, $esig) = ($1, $2, $3);
#                        log_red ">>>$file2, $1, $2, $3  >>>>";
                        for my $i (0..@event_dup2-1){
                            my ($keyname) = $event_dup2[$i] =~ /PostEvent_(\w+)/;
                            if($efield =~ /$keyname/i){
#                                log_yellow ">>>$file2 event $efield <> $event_dup2[$i] fount and add!!!";
                                $event_table{$event_dup2[$i]} = [$emethod, $esig];
                                splice @event_dup2, $i, 1;
                                last;
                            }
                        }
#                        log_red "eve: $1, $2, $3\n";
                    }
                }
                next;
            }

            if($cpp_table{$cpp}){
                my ($sigarg, $sigrval) = $cpp_table{$cpp}[0] =~ /\((.*)\)(.*)/;
                $flag = jni_signature_check($rval, $sigrval);
                if($flag == 0){
                    log_yellow "$cpp 's rval signature $sigrval was wrong!!!";
                }
                $flag = jni_signature_argcheck($args, $sigarg);
                if($flag == 0){
                    log_yellow "$cpp 's arg signature $sigarg was wrong!!!";
                }
                my $block = function_block_catch($FD);
                push @{$cpp_table{$cpp}}, $block;
            }
            log_blue "<$rval $cpp $args> not found in jni table!!!" if $flag == 0;
        }
    }
    close $FD;
    for my $eve (@event_dup){
        log_blue "<$file2, $eve> not defined!!!";
    }
    for my $eve (@event_dup2){
        log_blue "<$file2, $eve> not initialized!!!";
    }
    for my $eve (keys %event_table){
        unless ($event_table{$eve}){
            log_blue "<$file2, $eve> not found's event!!!";
            delete $event_table{$eve};
        }
    }
    return [\%java_table, \%cpp_table, \%event_table];
}

sub java_api_parser {
    my ($table, $file, $key) = @_;
    my $FD;
    my %java_table = %{$$table[0]};
    my %event_table = %{$$table[2]};
    my @event_table = values %event_table;
    open $FD, $file or warn "can't open $file $!\n";
    $file =~ s/.*\///;
    while(<$FD>){
		if(/^\s*(?:\b(public|private|protected)\b\s+)(?:\b(static|native|final)\b\s+)+/){
            #      (public|private|protected)     static final native xxxx
            if(/PostEvent/){
                #如果PostEvent不是static的，应该也找不到，static final native三者必须有1个或多个
                my ($rval, $name, $args) = /(\w+(?:\s*\[])?)\s+(\w+)\s*(\([^)]*\))/;
                #如果定义没有写在同一行，也是有问题的
                for my $i (0..@event_table-1){
                    my ($method, $jnisig) = @{$event_table[$i]};
                    if($name eq $method){
                        my ($sigarg, $sigrval) = $jnisig =~ /\((.*)\)(.*)/;
                        log_yellow "$file, $method, $jnisig is wrong!!!" unless java_signature_check($rval, $sigrval) and java_signature_argcheck($args, $sigarg);
                        splice @event_table, $i, 1;
                        last;
                    }
                }
            }
            if(/\bnative\b/){
                #这里检查的原因是有这样的：  public int abc; // this native field....
                my $flag = 0;
                while(not /;/){
                    my $newline = <$FD>;
                    s/\n/$newline/;
                }
                chomp;

                my ($rval, $name, $args) = /(\w+(?:\s*\[])?)\s+(\w+)\s*(\([^)]*\))/;
                # java 参数提取              ret_value []     method     (args)
                if (defined $java_table{$name}){
                    my @jnisig = keys $java_table{$name};
                    for my $jnisig (@jnisig) {
#                log_red "<<<<\033[1;34m  $_ $jnisig $java_table{$name}{$jnisig}  \033[0m>>>>\n";
                        unless ($flag){
                            my ($sigarg, $sigrval) = $jnisig =~ /\((.*)\)(.*)/;
#                        log_red "$_ $sigarg, $sigrval, $jnisig, $rval, $args\n";
                            $flag = (java_signature_check($rval, $sigrval) and java_signature_argcheck($args, $sigarg));
                            delete $java_table{$name}{$jnisig} if $flag;
#                    log_red "java: $_, $$entry[0], $$entry[2], $rval, $name, $args\n";
                        }
                    }
                    @jnisig = keys $java_table{$name};
                    unless( @jnisig){
                        delete $java_table{$name};
                    }
                }
                log_blue "<$file, $_> not found in jni table!!!" if $flag == 0;
            }
        }
    }
    close $FD;
    for my $method (keys %java_table){
        next if $method =~ /native_(init|setup|finalize)/;
        for my $jnisig (keys $java_table{$method}) {
            log_blue "<$file, $method => $jnisig> found in jni table but not in JAVA!!!";
        }
    }
    for my $e (@event_table){
        my ($method, $sig) = @$e;
        log_blue "<$file, $method, $sig> found in jni but not in JAVA!!!";
    }
}

sub cpp_api_parser {
    my ($table, $file, $key) = @_;
    my $FD;
    my $functioncall;
    my %cpp_table = %{$$table[1]};
    my @cpp_table = keys %cpp_table;
    my %event_table = %{$$table[2]};
    my @event_table = keys %event_table;
    my @event_exclude;
    my $cpp_count = @cpp_table;
    open $FD, $file or warn "can't open $file $!\n";
    $file =~ s/.*\///;
    while(<$FD>){
        if(/^\w*class \w+Listener/){
            #如果不是 xxxListener，也会出错
            next_event:
            while(<$FD>){
                last if(/^};/);
                my ($event) = /^\s*(?:virtual\s+)?(?:\w+\s+)(\w+)/;
                next unless $event;
#                log_red $file.$event.$_;
                for my $eve (@event_table){
                    next next_event if $eve == $event;
                }
                push @event_exclude, $event;
            }
        }
        if(/^public:/){
            while(<$FD>){
                last if(/^(private|protected):/);
                my ($rval, $cpp) = /^\s*(?:virtual|static)?\s*((?:const\s+)?\w+\s*(?:\*|&)?)??\s*(\w+)\s*\(/;
                #                      virtual|static            const      int  *         function (
                #                                  这里恳请不要写int const*或者int *const，或者const int *&之类
#                log_red "dotH: $rval, $cpp <$_>\n";
                if($cpp and $rval) {
                    next if $cpp =~ /^PostEvent/;
                    next if $cpp =~ /\b(setListener|connect|disconnect|notify|start|stop)\b/;
#                    next if $rval =~ /status_t/;
                    while(not /\)\s*(?:(?:const|=\s*0)\s*)?;/){
                        my $newline = <$FD>;
                        s/\n/$newline/;
                    }
                    chomp;
                    my $flag = 0;

                    for (my $i = 0; $i < $cpp_count; $i += 1){
#                        log_red "check function:$cpp >> $cpp_table[$i]\n";
                        if($cpp_table[$i] =~ /_$cpp(?:_\w+)?$/i){
                            #                _function_args
                            $flag = 1;
                            $functioncall = qr/$cpp\s?\(/;
                            #                function(
                            unless(@{$cpp_table{$cpp_table[$i]}}[1] =~ /$functioncall/){
                                log_cyan "$file: $cpp defined in jni but not implement!\n";
                                log_cyan "block:", @{$cpp_table{$cpp_table[$i]}}[1],"\n";
                            }
#                            log_red "delete function:$cpp $_\n";
                            splice @cpp_table, $i, 1;
                            $cpp_count -= 1;
                            last;
                        }
                    }
                    log_blue "<$file, $_> not found in jni table!!!" if $flag == 0;
                }
            }
        }
    }
    close $FD;
    for my $func (@cpp_table){
        next if $func =~ /native_(init|setup|finalize)/;
        log_blue "<$file, $func> found in jni table but not in dotH!!!";
    }
    for my $eve (@event_exclude){
        next if $eve =~ /notify|PostEvent_Template|PostEvent_SnServiceDeadth/;
        log_blue "<$file, $eve> found in dotH but not in jni!!!";
    }
}

dir_entry("$jni_tvapi_path",
    sub{
        my ($cpp) = @_;
        return unless $cpp =~ /.cpp$/;
        my $java = $cpp;
        $java =~ s/.*\/(.*).cpp$/\1.java/;
        $java =~ s/_/\//g;
        my $doth = $java;
        $doth =~ s/.*\/(.*).java$/\1/;
        my $key = $doth;
        $doth = lc($key)."/$key.h";
#                log_red "$cpp, $java, $doth, $key\n";
        my $table = jni_api_parser($cpp, $key);
        java_api_parser($table, "$java_tvapi_path/$java", $key);
        cpp_api_parser($table, "$inc_tvapi_path/$doth", $key);
    },
    qw/. .. com_mstar_android_tvapi_dtv_dvb_isdb_GingaManager.cpp/
    # 暂时跳过ginga的检查，因为不符合路径规则
);

log_black "black";
log_red "red";
log_green "green";
log_yellow "yellow";
log_blue "blue";
log_purple "purple";
log_cyan "cyan";
log_default "default";
