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

#sub realm_property_exists {
#    my ($self, $io, $property) = @_;
#
#    $self->_verify_known_io($io);
#
#    my $realm = $self->{'_io_realm'}{$io};
#
#    return exists($self->{'_realm_data'}{$realm}{$property}) ? 1 : 0;
#}

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
# XXX These “deep” methods seem a real kludge … but better than
# polymorphic?

#sub get_realm_deep_property {
#    my ($self, $io, $property) = @_;
#
#    my $realm = $self->_check_io_and_get_realm($io);
#
#    my ($hr, $key) = _resolve_deep_property(
#        $self->{'_realm_data'}{$realm},
#        $property,
#    );
#
#    return $hr->{$key};
#}

sub _resolve_deep_property {
    my ($hr, $prop_ar) = @_;

    my @prop = @$prop_ar;

    my $final_key = pop @prop;
    $hr = ($hr->{shift @prop} ||= {}) while @prop;

    return ($hr, $final_key);
}

sub set_realm_deep_property {
    my ($self, $io, $property, $value) = @_;

    my $realm = $self->_check_io_and_get_realm($io);

    my ($hr, $key) = _resolve_deep_property(
        $self->{'_realm_data'}{$realm},
        $property,
    );

    $hr->{$key} = $value;

    $self->_mark_for_removal_with_io( $io, $property );

    return $self;
}

sub unset_realm_deep_property {
    my ($self, $io, $property) = @_;

    my $realm = $self->_check_io_and_get_realm($io);

    #We don’t un-mark for removal since it will make no difference.

    my ($hr, $key) = _resolve_deep_property(
        $self->{'_realm_data'}{$realm},
        $property,
    );

    return delete $hr->{$key};
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

#left: HASH(0x7fbaa20bce78)
#right: HASH(0x7fbaa0a8d998)

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

    $self->_verify_known_io($io);

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

    #$self->_verify_known_io($io);

    my $realm = delete $self->{'_io_realm'}{$io};
    delete $self->{'_io_data'}{$io};

    $self->_do_removal_with_io($io, $realm);

    return $self;
}

#----------------------------------------------------------------------

sub _check_io_and_get_realm {
    my ($self, $io) = @_;

    $self->_verify_known_io($io);

    return $self->{'_io_realm'}{$io};
}

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

    if (my $remv_ar = delete $self->{'_remove_with_io'}{$io}) {
        for my $remv (@$remv_ar) {
            if (ref $remv) {
                my ($hr, $key) = _resolve_deep_property(
                    $self->{'_realm_data'}{$realm},
                    $remv,
                );

                delete $hr->{$key};
            }
            else {
                delete $self->{'_realm_data'}{$realm}{$remv};
            }
        }
    }

    return;
}

1;
