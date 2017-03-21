package Net::WAMP::Router::State::Memory;

#----------------------------------------------------------------------
# The default setup involves storing all of the router state in memory
# and depending on having a non-forking server.
#
# This abstraction should allow using an arbitrary storage backend
# and should accommodate a forking server.
#
# It’ll be complicated by the pattern of storing I/O objects. It might
# be worthwhile to play around with a forking server to see what’s what.
# At the same time, what would the advantage of a forking server be?
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Net::WAMP::Router::State );

sub new {
    return bless {}, shift;
}

#----------------------------------------------------------------------

sub get_realm_property {
    my ($self, $io, $property) = @_;

    $self->_verify_known_io($io);

    my $realm = $self->{'_io_realm'}{$io};

    return $self->{'_realm_data'}{$realm}{$property};
}

sub set_realm_property {
    my ($self, $io, $key, $value) = @_;

    $self->_verify_known_io($io);

    my $realm = $self->{'_io_realm'}{$io};

    $self->{'_realm_data'}{$realm}{$key} = $value;

    $self->_mark_for_removal_with_io( $io, $key );

    return $self;
}

sub unset_realm_property {
    my ($self, $io, $key) = @_;

    $self->_verify_known_io($io);

    my $realm = $self->{'_io_realm'}{$io};

    #We don’t un-mark for removal since it will make no difference.

    return $self->{'_realm_data'}{$realm}{$key};
}

#----------------------------------------------------------------------
#io determines a realm, but not vice-versa

sub add_io {
    my ($self, $io, $realm) = @_;

    if ($self->{'_io_data'}{$io}) {
        die "State $self already has IO $io!";
    }

    $self->{'_io_data'}{$io} = {};
    $self->{'_io_realm'}{$io} = $realm;

    return $self;
}

sub get_io_realm {
    my ($self, $io) = @_;

    $self->_verify_known_io($io);

    return $self->{'_io_realm'}{$io};
}

sub io_exists {
    my ($self, $io) = @_;

    return exists($self->{'_io_data'}{$io}) ? 1 : 0;
}

sub get_io_property {
    my ($self, $io, $key) = @_;

    $self->_verify_known_io();

    return $self->{'_io_data'}{$io}{$key};
}

sub set_io_property {
    my ($self, $io, $key, $value) = @_;

    $self->_verify_known_io($io);

    $self->{'_io_data'}{$io}{$key} = $value;

    return $self;
}

sub unset_io_property {
    my ($self, $io, $key) = @_;

    $self->_verify_known_io($io);

    return delete $self->{'_io_data'}{$io}{$key};
}

sub remove_io {
    my ($self, $io) = @_;

    $self->_verify_known_io($io);

    my $realm = delete $self->{'_io_realm'}{$io};

    $self->_do_removal_with_io($io, $realm);

    return $self;
}

#----------------------------------------------------------------------

sub _verify_known_io {
    my ($self, $io) = @_;

    if (!$self->{'_io_data'}{$io}) {
        die "IO object $io isn’t in state $self!";
    }

    return;
}

sub _mark_for_removal_with_io {
    my ($self, $io, $to_remv) = @_;

    push @{ $self->{'_remove_with_io'}{$io} }, $to_remv;

    return $self;
}

sub _do_removal_with_io {
    my ($self, $io, $realm) = @_;

    if (my $remv_ar = $self->{'_remove_with_io'}{$io}) {
        delete @{ $self->{'_realm_data'}{$realm} }{@$remv_ar};
    }

    return;
}

1;
