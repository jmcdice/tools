#!/usr/bin/perl
#
# Generate the nagios dashboard configuration.
# Joey <joseph.mcdonald@alcatel-lucent.com>

open FH, "> /var/www/config.php" or die "Can't write to /var/www/config.php: $!\n";

print FH '<?php
$api_type = "nagios-api";
$nagios_hosts = array(' . "\n";

for (`mojo --list|grep Cluster`) { 
   my ($c, $cluster) = split/\:/;
   $cluster =~ s/\s//g;
   my @tag = split/\./,$cluster;
   $ctag = uc @tag[0];

   next if ($cluster =~ /acid/i);

   my $html_color = uc `openssl rand -hex 3`;
   chomp $html_color;

   print FH qq|    array("hostname" => "$cluster", "port" => "6315", "protocol" => |
       . qq|"http", "tag" => "$ctag", "tagcolour" => "#$html_color"),\n|
}

print FH '
);

$filter = "";
$duration = 60*60;
$show_refresh_spinner = true;
$refresh_every_ms = 20000;
$sort_by_time = false;
$select_last_state_change_options = array(
    0 => "N/A", # DO NOT MODIFY THIS VALUE
    15 * 60 => "15 minutes",
    60 * 60 => "1 hour",
    60 * 60 * 12 => "12 hours",
    60 * 60 * 24 => "1 day",
    60 * 60 * 24 * 7 => "1 week"
);
$enable_blinking = false;
$extra_css = none;
';
