package IO::Framed::Blocking;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

IO::Framed::Blocking

=head1 SYNOPSIS

    my $io = IO::Framed::Blocking->new(
        $in_fh,
        $out_fh,

        #Optional, whatever “overbite” we might have read
        #from, e.g., a protocol handshake.
        $start_buffer,
    );

=head1 DESCRIPTION

A blocking I/O object. You can use this if you’re writing a client
or a forking server, but not if you’re writing a non-forking server.

=cut

use parent qw( IO::Framed );

use IO::SigGuard ();
use IO::Framed::X ();

use constant blocking => 1;

my $wrote;

sub write {
    local $!;

    IO::SigGuard::syswrite( $_[0]->{'_out_fh'}, $_[1] ) or do {
        die IO::Framed::X->create('WriteError', OS_ERROR => $!);
    };

    return;
}

1;
