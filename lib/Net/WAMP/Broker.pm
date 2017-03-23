package Net::WAMP::Broker;

use strict;
use warnings;

use Types::Serialiser ();

use Net::WAMP::Router::Features ();
use Protocol::WAMP::Utils ();

BEGIN {
    $Net::WAMP::Router::Features::FEATURES{'broker'}{'features'}{'publisher_exclusion'} = $Types::Serialiser::true;

    return;
}

sub subscribe {
    my ($self, $io, $options, $topic) = @_;

    my $subscribers_hr = $self->_get_topic_subscribers($io, $topic);

    if ($subscribers_hr->{$io}) {
        die "Already subscribed!";
    }

    my $subscription = Protocol::WAMP::Utils::generate_global_id();

    $self->{'_state'}->set_realm_deep_property(
        $io,
        [ "subscribers_$topic", $io ],
        {
            io => $io,
            options => $options,
            subscription => $subscription,
        },
    );
use Data::Dumper;
print STDERR Dumper('SUBSCRIBED', $self->{'_state'}{'_realm_data'});

    $self->{'_state'}->set_realm_property( $io, "subscription_topic_$subscription", $topic );

    return $subscription;
}

sub unsubscribe {
    my ($self, $io, $subscription) = @_;
printf STDERR "~~~~~ UNSUBSCRIBING: [$io / $subscription]\n";

    my $topic = $self->{'_state'}->unset_realm_property($io, "subscription_topic_$subscription") or do {
        my $realm = $self->_get_realm_for_tpt($io);
        die "Realm “$realm” has no subscription for ID “$subscription”!";
    };

    $self->{'_state'}->unset_realm_deep_property(
        $io, [ "subscribers_$topic", $io ],
    );

    return;
}

sub publish {
    my ($self, $io, $options, $topic, $args_ar, $args_hr) = @_;

    my $subscribers_hr = $self->_get_topic_subscribers($io, $topic);
my $realm = $self->_get_realm_for_tpt($io);
printf STDERR "----- subscribers ($realm:$topic): %d\n", scalar keys %$subscribers_hr;

    my $publication = Protocol::WAMP::Utils::generate_global_id();



    for my $rcp (values %$subscribers_hr) {

        #Implements “Publisher Exclusion” feature
        if ( $io eq $rcp->{'io'} ) {
            next if !Types::Serialiser::is_false($options->{'exclude_me'});
            my $exclusion = $self->{'_state'}->get_tpt_property($io, 'peer_roles')->{'publisher'}{'features'}{'publisher_exclusion'};
            next if !Types::Serialiser::is_true($exclusion);
        }
print STDERR "===SENDING TO $rcp->{'subscription'}\n";

        $self->_send_EVENT(
            $rcp->{'io'},
            $rcp->{'subscription'},
            $publication,
            {}, #TODO ???
            ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
        );
    }

    return $publication;
}

sub _get_topic_subscribers {
    my ($self, $io, $topic) = @_;
print STDERR "getting subscribers: $io - $topic\n";

    return $self->{'_state'}->get_realm_property($io, "subscribers_$topic");
}

#sub _get_topic_subscribers_or_die {
#    my ($self, $io, $topic) = @_;
#
#    return $self->_get_topic_subscribers($io, $topic) || do {
#        my $realm = $self->_get_realm_for_tpt($io);
#        die "Realm “$realm” has no topic “$topic”!";
#    };
#}

#----------------------------------------------------------------------

sub _receive_SUBSCRIBE {
    my ($self, $io, $msg) = @_;

    my $subscription = $self->subscribe(
        $io,
        ( map { $msg->get($_) } qw( Options Topic ) ),
    );

    return $self->_send_SUBSCRIBED(
        $io,
        $msg->get('Request'),
        $subscription,
    );
}

sub _send_SUBSCRIBED {
    my ($self, $io, $req_id, $sub_id) = @_;

    return $self->_create_and_send_msg(
        $io,
        'SUBSCRIBED',
        $req_id,
        $sub_id,
    );
}

sub _receive_UNSUBSCRIBE {
    my ($self, $io, $msg) = @_;

    $self->unsubscribe(
        $io,
        $msg->get('Subscription'),
    );

    $self->_send_UNSUBCRIBED( $io, $msg->get('Request') );

    return;
}

sub _send_UNSUBSCRIBED {
    my ($self, $io, $req_id) = @_;

    return $self->_create_and_send_msg(
        $io,
        'UNSUBSCRIBED',
        $req_id,
    );
}

sub _receive_PUBLISH {
    my ($self, $io, $msg) = @_;

    my $publication = $self->publish(
        $io,
        map { $msg->get($_) } qw(
            Options
            Topic
            Arguments
            ArgumentsKw
        ),
    );

    if (Types::Serialiser::is_true($msg->get('Options')->{'acknowledge'})) {
        $self->_send_PUBLISHED(
            $io,
            $msg->get('Request'),
            $publication,
        );
    }

    return;
}

sub _send_PUBLISHED {
    my ($self, $io, $req_id, $pub_id) = @_;

    return $self->_create_and_send_msg(
        $io,
        'PUBLISHED',
        $req_id,
        $pub_id,
    );
}

sub _send_EVENT {
    my ($self, $io, $sub_id, $pub_id, $details, @args) = @_;

    return $self->_create_and_send_msg(
        $io,
        'EVENT',
        $sub_id,
        $pub_id,
        $details,
        @args,
    );
}

1;
