package Net::WAMP::Message::REGISTER;

use parent qw( Net::WAMP::Base::SessionMessage );

use constant PARTS => qw( Request  Metadata  Procedure );

1;
