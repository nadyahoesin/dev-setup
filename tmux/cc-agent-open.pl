#!/usr/bin/perl
# Open a Claude Code subagent in Claude Code's own view, by pressing the keys.
#
#   cc-agent-open.pl <pane id> <registry file>     exit 0 = opened, 1 = could not
#   cc-agent-open.pl <pane id> main                back to the main agent, if a
#                                                  subagent is on screen
#   cc-agent-open.pl <pane id> names               press nothing: print, for each
#                                                  subagent in the list right now,
#                                                  "<id>\t<1 if on screen>\t<name>"
#                                                  (sidebar-list.sh reads this)
#
# The subagent view is drawn by the Claude process in its own pane, so nothing
# outside can show it: the only way in is the list under the prompt (↓ to focus
# it, ↑/↓ to pick a row, Enter to view). A row has no id, only how long the
# subagent has run, so the row is found the way sidebar-list.sh names it — by
# start time, which is when the registry file was made. Anything unexpected on
# screen (no list, subagent gone from it) and this gives up; the caller then
# falls back to the transcript viewer.
#
# Perl, not Python: this runs on a click, and Python takes ~95ms to start here
# against Perl's 2 — longer than everything else the click does put together.
use strict; use warnings; use utf8;
use Time::HiRes qw(time sleep);
binmode STDERR, ':utf8';

my $TMUX = '/opt/homebrew/bin/tmux';
my ($pane, $reg) = @ARGV;
my $main = $reg eq 'main';
my $names = $reg eq 'names';

# Giving up means the caller shows the transcript viewer instead of the real
# view, so every time it happens say why, with the list as it stood, in a log.
my @last_screen;
sub die_at {
  print STDERR "gave up at $_[0]\n" if $ENV{CCDBG};
  if (!$ENV{CCDRY} && open my $log, '>>:utf8', "$ENV{HOME}/.orchestrate-subagents/cc-open.log") {
    my @t = localtime; my $n = @last_screen < 12 ? @last_screen : 12;
    printf $log "%02d:%02d:%02d gave up at %s: pane %s target %s\n%s\n", @t[2, 1, 0], $_[0], $pane, $reg,
      join("\n", map { "    | " . substr($_, 0, 150) } @last_screen[-$n .. -1]);
    close $log;
  }
  exit 1;
}

# Claude Code redraws the list in pieces, and a read that lands between two of
# them sees half the old list and half the new — rows doubled, the cursor in
# two places. Only a frame that reads the same twice running is a frame.
sub screen {
  my @a = shot();
  for (1 .. 40) {
    sleep 0.004;
    my @b = shot();
    return @b if "@a" eq "@b";
    @a = @b;
  }
  return @a;
}

sub shot {
  open my $fh, '-|:utf8', $TMUX, 'capture-pane', '-p', '-t', $pane or die_at(0);
  my @l = <$fh>; close $fh; chomp @l;
  pop @l while @l && $l[-1] eq '';
  @last_screen = @l;
  return @l;
}

# The list at the bottom of the pane, top row first:
#   { cur => has the cursor, secs => seconds run (undef for main), exact, on => on screen }
# A long list is a window onto it — "↓ 7 more" under the rows, "↑ 1 more" on
# the main row — that scrolls with the cursor.
my ($more_up, $more_down);
sub rows {
  my @found; ($more_up, $more_down) = (0, 0);
  for my $line (reverse @_) {
    if ($line =~ /^(❯)?\s*((?:[├└│]\s*)*)([◯⏺])\s+(.*)$/) {   # ├ └: a subagent's own subagents, listed under it
      my ($cur, $kid, $dot, $rest) = ($1, $2 ne '', $3, $4);
      my ($type) = $rest =~ /^(\S+)/;
      $more_up = 1 if $rest =~ s/↑ \d+ more\s*$//;
      my ($secs, $exact);
      if ($rest =~ /\s{2,}((?:\d+h )?(?:\d+m )?\d+[sm]) · ↓/) {
        my $ran = $1; $secs = 0; $exact = $ran =~ /s$/;
        $secs += $1 * { h => 3600, m => 60, s => 1 }->{$2} while $ran =~ /(\d+)([hms])/g;
      }
      # a row with no time on it (a subagent in its first moment, or a pane
      # too narrow to show it) is still a row: it has to be counted to count
      # the cursor's way past it
      (my $bare = $rest) =~ s/\s+$//;
      my ($label) = $rest =~ /^\S+(?: \(\+\d+\))?\s{2,}(.*?)\s{2,}(?:\d+h )?(?:\d+m )?\d+[sm] · ↓/;
      unshift @found, { main => $bare eq 'main', cur => defined $cur, secs => $secs, exact => $exact, on => $dot eq '⏺', kid => $kid, type => $type, label => $label };
    } elsif ($line =~ /^\s*([↑↓]) \d+ more\s*$/) {
      $1 eq '↑' ? ($more_up = 1) : ($more_down = 1);
    } else {
      last if @found || $line =~ /\S/;
    }
  }
  return @found;
}

sub keys_ { return print STDERR "would press: @_\n" if $ENV{CCDRY}; system $TMUX, 'send-keys', '-t', $pane, @_ if @_ }   # one call: Claude Code takes them in order

sub cursor { my @l = @_; for my $i (0 .. $#l) { return $i if $l[$i]{cur} } return undef }

# Every subagent this pane has started, oldest first: when it started, when it
# was last restarted, and (once stopped) how long it ran.
my (@ents, $me);
unless ($main) {
  (my $dir = $reg) =~ s{/[^/]*$}{};
  $dir = "$ENV{HOME}/.orchestrate-subagents/cc/" . ($pane =~ s/^%//r) if $names;
  open my $fh, '-|', 'stat', '-f', '%FB %Fm %Fc %N', glob("$dir/*") or die_at(1);
  while (<$fh>) {
    chomp; my ($B, $m, $c, $n) = split ' ', $_, 4;
    # renamed when it stopped: ctime is the stop. Files that keep their own
    # clock (line 3: when it started; line 4: what it froze at on stopping)
    # say exactly what the row reads; older ones are guessed from the stat.
    my %e = (born => $B, again => $m, ran => $n =~ /\.done$/ ? $c - $B : -1e9, name => $n);
    if (open my $f, '<', $n) {
      my @ln = <$f>; close $f; chomp @ln;
      # its type, and whether another subagent started it: a row says both
      # (the type by name, the other by its ├ └), and a row can only be a
      # subagent that agrees with it on both
      $e{type} = $ln[1] // '';
      if (open my $mf, '<', ($ln[0] // '') . '.meta.json') { local $/; $e{kid} = <$mf> =~ /"parentAgentId":"/ ? 1 : 0; close $mf }
      if (defined $ln[2] && $ln[2] =~ /^\d+$/) {
        if ($n !~ /\.done$/) { $e{clock} = time - $ln[2] }
        elsif (defined $ln[3] && $ln[3] =~ /^\d+$/) { $e{clock} = $ln[3] }
      }
    }
    push @ents, \%e;
  }
  close $fh;
  @ents = sort { $a->{born} <=> $b->{born} || $a->{name} cmp $b->{name} } @ents;
  ($me) = grep { $ents[$_]{name} eq $reg } 0 .. $#ents;
  die_at(1) unless defined $me || $names;
}

sub find {   # index of the wanted row among the visible ones, or undef
  my @l = @_;
  if ($main) { for my $i (0 .. $#l) { return $i if $l[$i]{main} } return undef }
  my %row = pair(@l);
  return $row{$me};
}

sub pair {   # which visible row is which subagent: (index into @ents => index into the rows)
  my @l = @_;
  # A row has no id, only how long it has run: good to the second, while a
  # fan-out starts its subagents a second or two apart — nearest-in-time alone
  # opens the neighbour. But rows are in start order and so are the files, so
  # pair them up in order, whole list at once, for the least total error. A
  # running row counts up from its start (or last restart); a stopped one stays
  # at how long it ran. Rows and files with no partner are simply left out.
  my $now = time;
  my @r = grep { defined $l[$_]{secs} } 0 .. $#l;
  my $SKIP = 3.5;
  my (@cost, @pick);
  $cost[$_][0] = $_ * $SKIP for 0 .. @r;
  $cost[0][$_] = 0 for 0 .. @ents;
  for my $i (1 .. @r) {
    my $row = $l[$r[$i - 1]];
    for my $j (1 .. @ents) {
      my $e = $ents[$j - 1];
      my ($d) = defined $e->{clock} ? abs($row->{secs} - $e->{clock})
        : sort { $a <=> $b } abs($row->{secs} - $e->{ran}), map { abs($now - $row->{secs} - $_) } $e->{born}, $e->{again};
      my @opt;                                            # on a tie, the pairing wins
      push @opt, [$cost[$i - 1][$j - 1] + $d, 'both'] if $d <= ($row->{exact} ? 6 : 75)
        && !($row->{kid} xor $e->{kid} // 0) && (!$e->{type} || $e->{type} eq $row->{type});
      push @opt, [$cost[$i][$j - 1], 'ent'], [$cost[$i - 1][$j] + $SKIP, 'row'];
      my ($best) = sort { $a->[0] <=> $b->[0] } @opt;
      ($cost[$i][$j], $pick[$i][$j]) = @$best;
    }
  }
  my ($i, $j, %row) = (scalar @r, scalar @ents);
  while ($i > 0 && $j > 0) {
    my $p = $pick[$i][$j];
    if ($p eq 'both') { $row{$j - 1} = $r[$i - 1]; $i--; $j-- }
    elsif ($p eq 'row') { $i-- } else { $j-- }
  }
  return %row;
}

if ($names) {
  my @l = rows(shot());
  my %row = pair(@l);
  binmode STDOUT, ':utf8';
  for my $j (sort { $a <=> $b } keys %row) {
    my $r = $l[$row{$j}]; next unless defined $r->{label} && length $r->{label};
    (my $id = $ents[$j]{name}) =~ s{.*/}{}; $id =~ s/\.done$//;
    print "$id\t", ($r->{on} ? 1 : 0), "\t$r->{label}\n";
  }
  exit 0;
}

# The caller switches to this tab the moment we return, so do not return until
# Claude Code has drawn the view: otherwise the tab shows what was there before
# for the split second the redraw takes.
sub landed {
  for (1 .. 150) {
    my @l = rows(shot()); my $w = find(@l);   # a torn frame can only show it early, which is no harm here
    # …and, going back to main, until the ↑ after the Enter has handed the
    # focus back to the prompt: a click that arrives before it would count its
    # keys from a cursor that is about to leave the list.
    last if defined $w && $l[$w]{on} && !($main && defined cursor(@l));
    sleep 0.005;
  }
  exit 0;
}

sub settle {   # the list as redrawn after keys: poll until the cursor shows, briefly
  my @l;
  for (1 .. 40) { @l = rows(screen()); return @l if defined cursor(@l); sleep 0.005 }
  return @l;
}

my @done = $main ? ('Enter', 'Up') : ('Enter');           # main is the top row: one more ↑ hands the focus back to the prompt
sub go { my ($from, $to) = @_; (($to > $from ? 'Down' : 'Up') x abs($to - $from)) }
my @scr = screen();
my @lst = rows(@scr);
die_at(2) unless @lst;
my $want = find(@lst);
exit 0 if defined $want && $lst[$want]{on};               # already on screen
my $at = cursor(@lst);
unless (defined $at) {
  # The prompt has the focus. ↓ moves into the list — usually: the footer has
  # other things a ↓ can land on (a draft of several lines), so look before
  # pressing anything else, and step back out if it did not.
  # With an empty one-line prompt there is nothing else for it to land on,
  # and the ↓ always arrives on the top row: send everything at once. Waiting
  # to see the cursor first costs a whole redraw of a busy session.
  my ($box) = grep { $scr[$_] =~ /^❯/ && $scr[$_] !~ /^❯\s*[◯⏺]/ } reverse 0 .. $#scr;
  if (defined $want && defined $box && $box > 0 && $scr[$box - 1] =~ /^─/ && $scr[$box + 1] =~ /^─/
      && $scr[$box] =~ /^❯\s*(?:Message @\S+…)?\s*$/) {
    keys_('Down', go(0, $want), @done);
    landed();
  }
  keys_('Down');
  @lst = settle();
  $at = cursor(@lst);
  unless (defined $at) { keys_('Up'); die_at(3) }
  $want = find(@lst);
}
# Rows run oldest first, main on top. One not in the window is above it or
# below it by its start time; walk the cursor that way and the window follows.
# Leaves $want on its row (the cursor is not moved there yet), or returns 0.
sub reach {
  for (1 .. 60) {
    return 1 if defined $want;
    my $step = 'Up';
    unless ($main) {
      my ($oldest) = sort { $b <=> $a } grep { defined } map { $_->{secs} } @lst;
      return 0 unless defined $oldest;
      $step = 'Down' unless time - $ents[$me]{born} > $oldest + 20;
    }
    return 0 unless $step eq 'Up' ? $more_up : $more_down; # nothing hidden that way: it is not in the list
    my $edge = $step eq 'Up' ? 0 : $#lst;
    my @before = map { $_->{secs} // -1 } @lst;
    keys_(($step) x (abs($edge - $at) + 1));
    for (1 .. 40) {                                       # wait for the window to move
      @lst = rows(screen());
      last if "@{[map { $_->{secs} // -1 } @lst]}" ne "@before";
      sleep 0.005;
    }
    $at = cursor(@lst);
    return 0 unless defined $at;
    $want = find(@lst);
  }
  return 0;
}

sub redrawn {   # the list after keys that make it list more rows
  for (1 .. 150) {                                        # until the one we are after is listed
    @lst = rows(screen()); $at = cursor(@lst); $want = find(@lst);
    last if defined $at && defined $want;
    sleep 0.005;
  }
  die_at(6) unless defined $at;
}

unless (reach()) {
  # A subagent's own subagents are not rows of their own: Claude Code lists
  # them under their parent, and only while the parent is the one selected.
  # So go to the parent first, then to the child that appears beneath it.
  die_at(5) if $main;
  my $kid = $me; my $par;
  if (open my $f, '<', $ents[$kid]{name}) {
    chomp(my $base = <$f> // ''); close $f;
    if (open my $m, '<', "$base.meta.json") {
      local $/; my $meta = <$m>; close $m;
      if ($meta =~ /"parentAgentId":"([^"]+)"/) {
        my $id = $1;
        ($par) = grep { $ents[$_]{name} =~ m{/\Q$id\E(?:\.done)?$} } 0 .. $#ents;
      }
    }
  }
  die_at(5) unless defined $par;
  $me = $par; $want = find(@lst);
  reach() or die_at(8);
  # they are listed only once the parent is the one on screen
  keys_(go($at, $want), 'Enter');
  $me = $kid; redrawn();
  die_at(9) unless defined $want;
}
keys_(go($at, $want), @done);
landed();
