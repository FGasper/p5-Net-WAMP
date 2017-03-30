package Net::WAMP::Message::SUBSCRIBE;

use parent qw( Net::WAMP::Base::SessionMessage );

use constant PARTS => qw( Request  Metadata  Topic );

1;
