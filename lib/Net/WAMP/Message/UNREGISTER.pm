package Net::WAMP::Message::UNREGISTER;

use parent qw( Net::WAMP::Base::SessionMessage );

use constant PARTS => qw( Request  Registration );

1;
