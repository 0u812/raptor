#!/usr/bin/perl -w

use strict;

use File::Basename;
use LWP::Simple;

my $progname = basename $0;

my $offline=1;

my $manifest_URL='http://www.w3.org/2000/10/rdf-tests/rdfcore/Manifest.rdf';
my $local_tests_url='http://www.w3.org/2000/10/rdf-tests/rdfcore/';
my $local_tests_area=$ENV{HOME}.'/rdf/rdfcore/testcases/tests/';
my $local_manifest_file=$ENV{HOME}.'/rdf/rdfcore/testcases/tests/Manifest.rdf';

my $format="%-6s %5d %7.2f%%\n";


sub get_test_content($$) {
  my($url,$out_file)=@_;
  if ($url =~ m%^$local_tests_url(.*)$%) {
    my $in_file=$local_tests_area.$1;

    return $in_file if -r $in_file;

    open(IN, "<$in_file") or die "Cannot read $in_file ($url) - $!\n";
    open(OUT, ">$out_file") or die "Cannot write to $out_file - $!\n";
    print OUT join('', <IN>);
    close(IN);
    close(OUT);
  } else {
    return if $offline;
    mirror($url, $out_file);
  }

  return $out_file;
}


sub run_test($$$$$) {
  my($test_url, $is_positive, $is_verbose, $rdfxml_url, $ntriples_url)=@_;

  my $rdfxml_file=get_test_content($rdfxml_url, 'test.rdf');
  my $ntriples_file=$is_positive ? get_test_content($ntriples_url, 'test.nt') : undef;
 
  if(!-r $rdfxml_file || ($is_positive && ! -r $ntriples_file)) {
    return undef;
  }

  my $plabel=($is_positive) ? 'Positive' : 'Negative';

  if($is_verbose) {
    warn "$progname: $plabel Test $test_url\n";
    warn "  Input RDF/XML $rdfxml_url - $rdfxml_file \n";
    warn "  Output N-Triples $ntriples_url - $ntriples_file\n"
      if $ntriples_url;
  }

  my $cmd="./rdfdump -q -o ntriples file:$rdfxml_file '$rdfxml_url'";
  
  unlink 'test.err', 'parser.nt', 'expected.nt', 'test.ntc';
  my $status=system("$cmd 2>test.err >parser.nt");
  $status = ($status & 0xff00) >> 8;

  if($status > 128) {
    return ('SYSTEM', "$cmd failed - returned status $status\n");
  }

  # Nothing to compare to, it must be a negative test
  if(!$ntriples_url) { # && !$is_positive
    if($status) {
      return ('BAD', "$cmd failed\n");
    }
    return ('OK', "$cmd succeeded");
  }

  open(NT,"<$ntriples_file") or die "Cannot read $ntriples_file - $!\n";
  open(NT2,">expected.nt") or die "Cannot create expected.nt - $!\n";
  while(<NT>) {
    next if /^\s*\#/;
    next if /^\s*$/;
    print NT2;
  }
  close(NT);
  close(NT2);

  $cmd="./ntc parser.nt expected.nt > test.ntc";
  $status=system("$cmd 2>&1 >/dev/null");
  $status = ($status & 0xff00) >> 8;

  if($status > 2) {
    return ('SYSTEM', "$cmd failed - returned status $status\n");
  }

  if($status == 1) {
    my $msg=`diff -u expected.nt parser.nt | tail +3`;
    return ('BAD', "N-Triples match failed\n$msg");
  }

  if($status == 2) {
    return ('WARNING', "N-Triples matched with warnings\n");
  }

  return ('OK', "N-Triples matched");
}


sub read_err($) {
  my($err)=@_;
  open(ERR,"<$err") or die "Cannot read $err - $!\n";
  $err=join('', grep(!/(?:raptor_|^\s*attributes|^\s*$)/, <ERR>));
  close(ERR);
  return $err;
}

sub run_tests($$$$@) {
  my($tests,$is_verbose,$results,$totals,@test_urls)=@_;

  for my $test (@test_urls) {

    if(!$tests->{$test}) {
      warn "$progname: No such test $test, skipping\n";
      next;
    }
       
    my $is_positive=$tests->{$test}->{positive};
    my $plabel=($is_positive) ? 'Positive' : 'Negative';
    my $inputs=$tests->{$test}->{'test:inputDocument'};
    my $outputs=$tests->{$test}->{'test:outputDocument'};

    if(!defined $inputs || !$inputs->{'test:RDF-XML-Document'}
       ||scalar(@{$inputs->{'test:RDF-XML-Document'}}) !=1) {
      die "$plabel Test $test has not got exactly 1 input RDF/XML file\n";
    }
    
    if($is_positive) {
      if(!defined $outputs || !$outputs->{'test:NT-Document'}
	 ||scalar(@{$outputs->{'test:NT-Document'}}) !=1) {
	die "$plabel Test $test has not got exactly 1 output N-Triple file\n";
      }
    }

    my $input_rdfxml=$inputs->{'test:RDF-XML-Document'}->[0];
    my $output_ntriples=$is_positive ? $outputs->{'test:NT-Document'}->[0] : undef;

    my($result,$msg)=run_test($test, $is_positive, $is_verbose, 
			      $input_rdfxml, $output_ntriples);

    if($result eq 'SYSTEM') {
      my $err=read_err('test.err');
      $msg .= "\n".$err;
      warn "Test $test SYSTEM ERROR: $msg\n";
      push(@{$totals->{SYSTEM}}, $test);
    } elsif($result eq 'OK') {
      if($is_positive) {
	push(@{$totals->{OK}}, $test);
      } else {
	open(TOUT,"<parser.nt") or die "Cannot read parser.nt - $!\n";
	my $out=join("\n  ", <TOUT>);
	close(TOUT);
	$msg= "  ".$out;
	warn "$plabel Test $test SUCCEEDED, should have failed - returned: \n$msg\n";
	push(@{$totals->{BAD}}, $test);
      }
    } else {
      if($is_positive) {
	my $err=read_err('test.err');
	$msg .= "\n".$err;
	warn "$plabel Test $test FAILED - $msg\n";
	push(@{$totals->{BAD}}, $test);
      } else {
	push(@{$totals->{OK}}, $test);
      }
    }

    $results->{$test}=$result;
  }

}


sub summarize_results($$$$) {
  my($title, $results, $totals, $total)=@_;

  warn "Results for $title\n";
  for my $type (sort keys %$totals) {
    my(@rt)=@{$totals->{$type}};
    my(@short_rt)=map {s/^$local_tests_url//; $_} @rt;
    print sprintf($format,$type, scalar(@rt), (int(scalar(@rt)/$total*10000))/100);
  }
  print sprintf($format, 'TOTAL', $total, '100');
}


my(%tests);

my(@positive_test_urls);
my(@negative_test_urls);
my(@approved_positive_test_urls);
my(@approved_negative_test_urls);

if($offline) {
  warn "$progname: OFFLINE - using stored manifest URL $manifest_URL\n";
} else {
  warn "$progname: Checking mirrored manifest URL $manifest_URL\n";
  if(mirror($manifest_URL, $local_manifest_file ) == RC_NOT_MODIFIED) {
    warn "$progname: OK, not modified\n";
  } else {
    warn "$progname: Unknown error\n";
  }
}

# Content from the file
my $content='';
open(IN, "<$local_manifest_file") or die "Cannot read $local_manifest_file - $!\n";
$content .= join('',<IN>);
close($content);

# Remove comments
1 while $content =~ s/<!-- .+? -->//gs;

# Unify blanks
$content =~ s/\s+/ /gs;
$content =~ s/\s*$//s;

# Remove everything but tests
$content =~ s%^<\?xml version="1.0"\?> <rdf:RDF[^>]+>%%;
$content =~ s%</rdf:RDF>$%%s;

# Find the tests
while(length $content) {
  $content =~ s/^\s+//;
  last if !length $content;
  if($content =~ s%^<test:(Positive|Negative)ParserTest rdf:about="([^"]+)">(.+?)</test:(Positive|Negative)ParserTest>%%) { # "
    my($type,$url,$test_content)=($1,$2,$3);
    while(length $test_content) {
      $test_content =~ s/^\s+//;
      last if !length $test_content;
      if($test_content =~ s%^<(\S+) rdf:resource="([^"]+)"\s*/>%%) { #"
        $tests{$url}->{$1}=$2;
      } elsif ($test_content =~ s%^<(test:\w+)>\s*<(test:[-\w]+) rdf:about="([^"]+)"\s*/>\s*</(test:\w+)>%%) { #"
        push(@{$tests{$url}->{$1}->{$2}}, $3);
      } elsif ($test_content =~ s%^<(test:\w+)>([^<]+)</test:\w+>%%) {
        $tests{$url}->{$1}=$2;
      } else {
	die "I'm stumped at test content >>$test_content<<\n";
      }

    }

    my $test_status=$tests{$url}->{'test:status'} || '';
    if ($test_status eq 'OBSOLETED') {
      warn "$progname: Ignoring Obsolete Test URL $url\n";
      next;
    }
 
    if ($type eq 'Positive') {
      push(@positive_test_urls, $url);
      $tests{$url}->{positive}=1;
    } else {
      push(@negative_test_urls, $url);
    }

    if ($test_status eq 'APPROVED') {
      if ($type eq 'Positive') {
	push(@approved_positive_test_urls, $url);
      } else {
	push(@approved_negative_test_urls, $url);
      }
    }

  } elsif($content =~ s%^<test:(Positive|Negative)EntailmentTest rdf:about="([^"]+)">(.+?)</test:(Positive|Negative)EntailmentTest>%%) { # "
  } elsif($content =~ s%^<test:MiscellaneousTest rdf:about="([^"]+)">(.+?)</test:MiscellaneousTest>%%) { # "
     warn "$progname: Ignoring Miscellaneous Test URL $1\n";
  } else {
    die "I'm stumped at content >>$content<<\n";
  }
}


warn "$progname: Parser tests found:\n";
warn "$progname:   Positive: ",scalar(@positive_test_urls),"\n";
warn "$progname:   Negative: ",scalar(@negative_test_urls),"\n";

warn "$progname: APPROVED parser tests found:\n";
warn "$progname:   Positive: ",scalar(@approved_positive_test_urls),"\n";
warn "$progname:   Negative: ",scalar(@approved_negative_test_urls),"\n";



my(%results);

if(@ARGV) {
  my(%totals);
  warn "$progname: Running user parser tests:\n";
  run_tests(\%tests, 1, \%results, \%totals, @ARGV);

  summarize_results("User Parser Tests", \%results, \%totals, scalar(@ARGV));
  exit 0;
}

my(%positive_totals)=();
run_tests(\%tests, 0, \%results, \%positive_totals, @positive_test_urls);
summarize_results("Positive Parser Tests", \%results, \%positive_totals, scalar(@positive_test_urls));

print "\n\n";

my(%negative_totals)=();
run_tests(\%tests, 0, \%results, \%negative_totals, @negative_test_urls);
summarize_results("Negative Parser Tests", \%results, \%negative_totals, scalar(@negative_test_urls));
