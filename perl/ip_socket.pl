#!/bin/perl
use strict;
use warnings;
use Socket;
my $address = '192.168.0.15/13';
my @array = split(/\//, $ARGV[0]);
my $ip_address = $array[0];
my $netmask = $array[1];

my $ip_address_binary = inet_aton( $ip_address );
my $netmask_binary    = ~pack("N", (2**(32-$netmask))-1);

my $network_address    = inet_ntoa( $ip_address_binary & $netmask_binary );
my $first_valid        = inet_ntoa( pack( 'N', unpack('N', $ip_address_binary & $netmask_binary ) + 1 ));
my $last_valid         = inet_ntoa( pack( 'N', unpack('N', $ip_address_binary | ~$netmask_binary ) - 1 ));
my $broadcast_address  = inet_ntoa( $ip_address_binary | ~$netmask_binary );
my $dottednetmask	 = inet_ntoa($netmask_binary);

my $currentup = unpack('N', $ip_address_binary & $netmask_binary) + 1;
my $current = $first_valid;
print "network: \t", $network_address, "\n";
print "first valid: \t", $first_valid, "\n";
print "last valid: \t", $last_valid, "\n";
print "broadcast: \t", $broadcast_address, "\n";
while ($netmask <= 30 && $current ne $last_valid) {
	print $current,, " ", $dottednetmask , "\n";
	$currentup++;
	$current = inet_ntoa( pack( 'N', $currentup));
}

exit;