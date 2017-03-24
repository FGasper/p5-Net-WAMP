package Net::WAMP::Utils;

use strict;
use warnings;

#Operates on $_
#sub to_bool {
#    my ($val) = @_;
#    return ${ *{$Types::Serialiser::{ $val ? 'true' : 'false' }}{'SCALAR'} };
#}

#For:
#   - WELCOME.Session
#   - PUBLISHED.Publication
#   - EVENT.Publication
#
#cf. https://tools.ietf.org/html/draft-oberstet-hybi-tavendo-wamp-02#page-14
#
sub generate_global_id {
    die "64-bit systems only for now!" if length(pack 'l!', 0) < 8;

    #Between 0 and 2^53 (9_007_199_254_740_992), inclusive.
    #It must serialize as a number, which means we need Perl to represent
    #this value internally with an Iv, not a Pv. Which means we can only
    #support 64-bit systems for now.
    return int rand 9_007_199_254_740_993;

    #----------------------------------------------------------------------

    #my $rnd1 = rand 65536;  #16 bits
    #my $rnd2 = rand 65536;  #+ 16 = 32 bits
    #my $rnd3 = rand 65536;  #+ 16 = 48 bits
    #my $rnd4 = rand 16;     #+ 4  = 52 bits
    #my $packed = pack 'SSSS', $rnd4, $rnd3, $rnd2, $rnd1;

    #Support non-64-bit systems to find an integer
    #between 0 and 2^53 (9_007_199_254_740_992), inclusive.

    my $start = int rand 9008;

    my @parts;
    if ($start == 9007) {
        my $next6 = int rand 199_255;
        push @parts, $next6;

        if ($next6 == 199254) {
            push @parts, int rand 740_993;
        }
    }

    while (@parts < 2) {
        push @parts, int rand 1_000_000;
    }

    #Make sure these take up 6 decimal points
    $_ = sprintf '%06d', $_ for @parts;

    my $id = join q<>, $start, @parts;

    #strip leading “0”
    $id =~ s<\A0+><>;

    return $id;
}

1;
