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

    $subscribers_hr->{$io} = {
        io => $io,
        options => $options,
        subscription => $subscription,
    };

    #Unnecessary for the Memory-type State object if there are already
    #topic subscribers, but no harm, either.
    $self->{'_state'}->set_realm_property(
        $io, "subscribers_$topic", $subscribers_hr,
    );

    $self->{'_state'}->set_realm_property( $io, "subscription_topic_$subscription", $topic );

    return $subscription;
}

sub unsubscribe {
    my ($self, $io, $subscription) = @_;

    my $topic = $self->{'_state'}->unset_realm_property($io, "subscription_topic_$subscription") or do {
        my $realm = $self->_get_realm_for_io($io);
        die "Realm “$realm” has no subscription for ID “$subscription”!";
    };

    my $subscribers_hr = $self->_get_topic_subscribers_or_die($io, $topic);

    delete $subscribers_hr->{$io};

    #Unnecessary for the Memory-type State object, but no harm, either.
    $self->{'_state'}->set_realm_property(
        $io, "subscribers_$topic", $subscribers_hr,
    );

    return;
}

sub publish {
    my ($self, $io, $options, $topic, $args_ar, $args_hr) = @_;

    my $subscribers_hr = $self->_get_topic_subscribers_or_die($io, $topic);

    my $publication = Protocol::WAMP::Utils::generate_global_id();

    #Implements “Publisher Exclusion” feature
    my $include_me = Types::Serialiser::is_false($options->{'exclude_me'});
    $include_me &&= $self->{'_state'}->get_io_property($io, 'peer_roles')->{'publisher'}{'features'}{'publisher_exclusion'};
    $include_me &&= Types::Serialiser::is_true($include_me);

    for my $rcp (values %$subscribers_hr) {
        if ( $include_me || ($io ne $rcp->{'io'}) ) {
            $self->_send_EVENT(
                $rcp->{'io'},
                $rcp->{'subscription'},
                $publication,
                {}, #TODO ???
                ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
            );
        }
    }

    return $publication;
}

sub _get_topic_subscribers {
    my ($self, $io, $topic) = @_;
print STDERR "getting subscribers: $io - $topic\n";

    return $self->{'_state'}->get_realm_property($io, "subscribers_$topic");
}

sub _get_topic_subscribers_or_die {
    my ($self, $io, $topic) = @_;

    return $self->_get_topic_subscribers($io, $topic) || do {
        my $realm = $self->_get_realm_for_io($io);
        die "Realm “$realm” has no topic “$topic”!";
    };
}

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
