package Net::WAMP::Role::Broker;

use strict;
use warnings;

use parent qw(
  Net::WAMP::Role::Base::Router
);

use Types::Serialiser ();

use Net::WAMP::Role::Base::Router::Features ();
use Net::WAMP::Utils ();

BEGIN {
    $Net::WAMP::Role::Base::Router::Features::FEATURES{'broker'}{'features'}{'publisher_exclusion'} = $Types::Serialiser::true;

    return;
}

sub subscribe {
    my ($self, $session, $options, $topic) = @_;

    my $subscribers_hr = $self->_get_topic_subscribers($session, $topic);

    if ($subscribers_hr->{$session}) {
        die "Already subscribed!";
    }

    my $subscription = Net::WAMP::Utils::generate_global_id();

    $self->{'_state'}->set_realm_deep_property(
        $session,
        [ "subscribers_$topic", $session ],
        {
            session => $session,
            options => $options,
            subscription => $subscription,
        },
    );

    $self->{'_state'}->set_realm_property( $session, "subscription_topic_$subscription", $topic );

    return $subscription;
}

sub unsubscribe {
    my ($self, $session, $subscription) = @_;

    my $topic = $self->{'_state'}->unset_realm_property($session, "subscription_topic_$subscription") or do {
        my $realm = $self->_get_realm_for_session($session);
        die "Realm “$realm” has no subscription for ID “$subscription”!";
    };

    $self->{'_state'}->unset_realm_deep_property(
        $session, [ "subscribers_$topic", $session ],
    );

    return;
}

sub publish {
    my ($self, $session, $options, $topic, $args_ar, $args_hr) = @_;

    my $subscribers_hr = $self->_get_topic_subscribers($session, $topic);

    my $publication = Net::WAMP::Utils::generate_global_id();

    for my $rcp (values %$subscribers_hr) {

        #Implements “Publisher Exclusion” feature
        if ( $session eq $rcp->{'session'} ) {
            next if !Types::Serialiser::is_false($options->{'exclude_me'});
            my $exclusion = $self->{'_state'}->get_session_property($session, 'peer_roles')->{'publisher'}{'features'}{'publisher_exclusion'};
            next if !Types::Serialiser::is_true($exclusion);
        }

        $self->_send_EVENT(
            $rcp->{'session'},
            $rcp->{'subscription'},
            $publication,
            {}, #TODO ???
            ( $args_ar ? ( $args_ar, $args_hr || () ) : () ),
        );
    }

    return $publication;
}

sub _get_topic_subscribers {
    my ($self, $session, $topic) = @_;

    return $self->{'_state'}->get_realm_property($session, "subscribers_$topic");
}

#sub _get_topic_subscribers_or_die {
#    my ($self, $session, $topic) = @_;
#
#    return $self->_get_topic_subscribers($session, $topic) || do {
#        my $realm = $self->_get_realm_for_session($session);
#        die "Realm “$realm” has no topic “$topic”!";
#    };
#}

#----------------------------------------------------------------------

sub _receive_SUBSCRIBE {
    my ($self, $session, $msg) = @_;

    my $subscription = $self->subscribe(
        $session,
        ( map { $msg->get($_) } qw( Options Topic ) ),
    );

    return $self->_send_SUBSCRIBED(
        $session,
        $msg->get('Request'),
        $subscription,
    );
}

sub _send_SUBSCRIBED {
    my ($self, $session, $req_id, $sub_id) = @_;

    return $self->_create_and_send_msg(
        $session,
        'SUBSCRIBED',
        $req_id,
        $sub_id,
    );
}

sub _receive_UNSUBSCRIBE {
    my ($self, $session, $msg) = @_;

    $self->unsubscribe(
        $session,
        $msg->get('Subscription'),
    );

    $self->_send_UNSUBCRIBED( $session, $msg->get('Request') );

    return;
}

sub _send_UNSUBSCRIBED {
    my ($self, $session, $req_id) = @_;

    return $self->_create_and_send_msg(
        $session,
        'UNSUBSCRIBED',
        $req_id,
    );
}

sub _receive_PUBLISH {
    my ($self, $session, $msg) = @_;

    my $publication = $self->publish(
        $session,
        map { $msg->get($_) } qw(
            Options
            Topic
            Arguments
            ArgumentsKw
        ),
    );

    if (Types::Serialiser::is_true($msg->get('Options')->{'acknowledge'})) {
        $self->_send_PUBLISHED(
            $session,
            $msg->get('Request'),
            $publication,
        );
    }

    return;
}

sub _send_PUBLISHED {
    my ($self, $session, $req_id, $pub_id) = @_;

    return $self->_create_and_send_msg(
        $session,
        'PUBLISHED',
        $req_id,
        $pub_id,
    );
}

sub _send_EVENT {
    my ($self, $session, $sub_id, $pub_id, $details, @args) = @_;

    return $self->_create_and_send_msg(
        $session,
        'EVENT',
        $sub_id,
        $pub_id,
        $details,
        @args,
    );
}

1;
