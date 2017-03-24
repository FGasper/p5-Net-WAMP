package Net::WAMP::Router::State::Memory;

#----------------------------------------------------------------------
# The default setup involves storing all of the router state in memory
# and depending on a non-forking server.
#
# This abstraction should allow using an arbitrary storage backend
# and should accommodate a forking server.
#
# At the same time, what would the advantage of a forking server be?
# Anyway, if nothing else it’s a nice abstraaction. So, here’s this.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Net::WAMP::Router::State );

sub new {
    return bless {}, shift;
}

#----------------------------------------------------------------------

#sub realm_property_exists {
#    my ($self, $tpt, $property) = @_;
#
#    $self->_verify_known_tpt($tpt);
#
#    my $realm = $self->{'_tpt_realm'}{$tpt};
#
#    return exists($self->{'_realm_data'}{$realm}{$property}) ? 1 : 0;
#}

sub get_realm_property {
    my ($self, $tpt, $property) = @_;

    $self->_verify_known_tpt($tpt);

    my $realm = $self->{'_tpt_realm'}{$tpt};

    return $self->{'_realm_data'}{$realm}{$property};
}

sub set_realm_property {
    my ($self, $tpt, $key, $value) = @_;

    $self->_verify_known_tpt($tpt);

    my $realm = $self->{'_tpt_realm'}{$tpt};

    $self->{'_realm_data'}{$realm}{$key} = $value;

    $self->_mark_for_removal_with_tpt( $tpt, $key );

    return $self;
}

sub unset_realm_property {
    my ($self, $tpt, $key) = @_;

    $self->_verify_known_tpt($tpt);

    my $realm = $self->{'_tpt_realm'}{$tpt};

    #We don’t un-mark for removal since it will make no difference.

    return $self->{'_realm_data'}{$realm}{$key};
}

#----------------------------------------------------------------------
# XXX These “deep” methods seem a real kludge … but better than
# polymorphic?

#sub get_realm_deep_property {
#    my ($self, $tpt, $property) = @_;
#
#    my $realm = $self->_check_tpt_and_get_realm($tpt);
#
#    my ($hr, $key) = _resolve_deep_property(
#        $self->{'_realm_data'}{$realm},
#        $property,
#    );
#
#    return $hr->{$key};
#}

sub set_realm_deep_property {
    my ($self, $tpt, $property, $value) = @_;

    my $realm = $self->_check_tpt_and_get_realm($tpt);

    my ($hr, $key) = _resolve_deep_property(
        $self->{'_realm_data'}{$realm},
        $property,
    );

    $hr->{$key} = $value;

    $self->_mark_for_removal_with_tpt( $tpt, $property );

    return $self;
}

sub unset_realm_deep_property {
    my ($self, $tpt, $property) = @_;

    my $realm = $self->_check_tpt_and_get_realm($tpt);

    #We don’t un-mark for removal since it will make no difference.

    my ($hr, $key) = _resolve_deep_property(
        $self->{'_realm_data'}{$realm},
        $property,
    );

    return delete $hr->{$key};
}

sub _resolve_deep_property {
    my ($hr, $prop_ar) = @_;

    my @prop = @$prop_ar;

    my $final_key = pop @prop;
    $hr = ($hr->{shift @prop} ||= {}) while @prop;

    return ($hr, $final_key);
}

#----------------------------------------------------------------------
#transport determines a realm, but not vice-versa

sub add_transport {
    my ($self, $tpt, $realm) = @_;

    if ($self->{'_tpt_data'}{$tpt}) {
        die "State $self already has IO $tpt!";
    }

    $self->{'_tpt_data'}{$tpt} = {};
    $self->{'_tpt_realm'}{$tpt} = $realm;

    return $self;
}

sub get_transport_realm {
    my ($self, $tpt) = @_;

    $self->_verify_known_tpt($tpt);

    return $self->{'_tpt_realm'}{$tpt};
}

sub transport_exists {
    my ($self, $tpt) = @_;

    return exists($self->{'_tpt_data'}{$tpt}) ? 1 : 0;
}

sub get_transport_property {
    my ($self, $tpt, $key) = @_;

    $self->_verify_known_tpt($tpt);

    return $self->{'_tpt_data'}{$tpt}{$key};
}

sub set_transport_property {
    my ($self, $tpt, $key, $value) = @_;

    $self->_verify_known_tpt($tpt);

    $self->{'_tpt_data'}{$tpt}{$key} = $value;

    return $self;
}

sub unset_transport_property {
    my ($self, $tpt, $key) = @_;

    $self->_verify_known_tpt($tpt);

    return delete $self->{'_tpt_data'}{$tpt}{$key};
}

sub forget_transport {
    my ($self, $tpt) = @_;

    #Be willing to accept no-op forgets.
    #$self->_verify_known_tpt($tpt);

    my $realm = delete $self->{'_tpt_realm'}{$tpt};
    delete $self->{'_tpt_data'}{$tpt};

    $self->_do_removal_with_tpt($tpt, $realm);

    return $self;
}

#----------------------------------------------------------------------

sub _check_tpt_and_get_realm {
    my ($self, $tpt) = @_;

    $self->_verify_known_tpt($tpt);

    return $self->{'_tpt_realm'}{$tpt};
}

sub _verify_known_tpt {
    my ($self, $tpt) = @_;

    if (!$self->{'_tpt_data'}{$tpt}) {
        die "IO object $tpt isn’t in state $self!";
    }

    return;
}

sub _mark_for_removal_with_tpt {
    my ($self, $tpt, $to_remv) = @_;

    push @{ $self->{'_remove_with_tpt'}{$tpt} }, $to_remv;

    return $self;
}

sub _do_removal_with_tpt {
    my ($self, $tpt, $realm) = @_;

    if (my $remv_ar = delete $self->{'_remove_with_tpt'}{$tpt}) {
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
