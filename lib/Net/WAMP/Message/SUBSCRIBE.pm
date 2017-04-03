package Net::WAMP::Message::SUBSCRIBE;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::SessionMessage );

use constant PARTS => qw( Request  Metadata  Topic );

1;
