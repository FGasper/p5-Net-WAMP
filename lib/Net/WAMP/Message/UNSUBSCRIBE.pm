package Net::WAMP::Message::UNSUBSCRIBE;

use parent qw( Net::WAMP::Base::SessionMessage );

use constant PARTS => qw( Request  Subscription );

1;
