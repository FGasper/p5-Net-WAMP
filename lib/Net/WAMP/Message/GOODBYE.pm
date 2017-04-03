package Net::WAMP::Message::GOODBYE;

use strict;
use warnings;

use parent qw( Net::WAMP::Base::Message );

use constant PARTS => qw( Metadata  Reason );

1;
