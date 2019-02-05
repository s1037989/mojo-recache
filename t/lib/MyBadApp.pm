package MyBadApp;
use Mojo::Base -base;

sub array { shift; [@_] }
sub slow { sleep @_>1 ? pop : 1 }

1;
