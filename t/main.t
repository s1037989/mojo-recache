use Test::More;

use Mojo::Recache;

use FindBin;
use lib "$FindBin::Bin/lib";

use MyApp;
use MyApp1;

sub array { return [@_] }
sub hash  { return {@_} }
sub array1 { return [@_] }
sub hash1  { return {@_} }

Mojo::Recache->new->home->tap(sub{$_->remove_tree if $_->basename eq 'recache'});

{
  my $recache = Mojo::Recache->new('Storable');
  $recache->add_method(array => 'daily');
  $recache->add_method(hash  => 'weekly');
  $recache->overload(1);
  my $array = $recache->array(14..17);
  isa_ok $array, 'Mojo::Recache::Cache::overload';
  isa_ok $array, 'Mojo::Recache::Cache';
  isa_ok $$array, 'Mojo::Recache::Cache';
  is $array->[0], 14;
  is $$array->data->[0], 14;
  isa_ok $$array->file, 'Mojo::File';
  $array = $recache->array(5..18);
  my $array_name = $array->name;
  isa_ok $array, 'Mojo::Recache::Cache';
  is $array->data->[0], 5;
  is $array->cached, 0;
  isa_ok $array->file, 'Mojo::File';
  $array = $recache->overload(1)->array(6..12);
  isa_ok $array, 'Mojo::Recache::Cache::overload';
  isa_ok $array, 'Mojo::Recache::Cache';
  isa_ok $$array, 'Mojo::Recache::Cache';
  is $array->[0], 6;
  is $$array->data->[0], 6;
  isa_ok $$array->file, 'Mojo::File';
  $array = $recache->array(7..12);
  isa_ok $array, 'Mojo::Recache::Cache';
  is $array->data->[0], 7;
  isa_ok $array->file, 'Mojo::File';
  isa_ok $array->recache->home, 'Mojo::Home';
  my $hash = $recache->hash(id=>12);
  isa_ok $hash, 'Mojo::Recache::Cache';
  isa_ok $hash, 'HASH';
  $hash = $recache->overload(1)->hash(id=>12);
  is $hash->{id}, 12;
  is $$hash->data->{id}, 12;
  $array = $recache->cache(daily => $array_name);
  is $array->cached, 1;
  is $array->data->[0], 5;
  $array = $recache->overload(1)->cache(daily => $array_name);
  is $array->[0], 5;
};

{
  my $recache = Mojo::Recache->new('Storable');
  $recache->add_method(array => 'daily');
  is $recache->overload(1)->array(3..6)->[0], 3;
};

{
  my $recache = Mojo::Recache->new('Storable');
  $recache->add_method([qw/array array1/] => 'daily');
  is $recache->overload(1)->array(3..6)->[0], 3;
  is $recache->overload(1)->array1(13..16)->[0], 13;
};

{
  my $recache = Mojo::Recache->new('Storable');
  $recache->add_methods([array => 'daily'], [array1 => 'yearly']);
  is $recache->overload(1)->array(3..6)->[0], 3;
  is $recache->overload(1)->array1(13..16)->[0], 13;
  is $recache->array(3..6)->queue, 'daily';
  is $recache->array1(13..16)->queue, 'yearly';
};

{
  my $app = MyApp->new;
  $app->recache->backend->once(retrieved => sub { warn pop });
  $app->recache->backend->once(stored => sub { warn pop->name });
  is $app->recache->overload(1)->array2(3..6)->[0], -3;
  is $app->recache->overload(1)->array2(3..6)->[0], -3;
  my $overload = $app->recache->overload(1)->array2(3..6);
  is $overload->[0], -3;
  is $$overload->data->[0], -3;
  is $$overload->cached, 1;
  my $normal = $app->recache->array2(4..6);
  is $normal->data->[0], -4;
  is $normal->cached, 0;
  is $app->recache->array2(4..6)->cached, 1;
  is $app->recache->overload(1)->array(3..6)->[0], -3;

  my $app1 = MyApp1->new;
  is $app1->recache->overload(1)->array2(3..6)->[0], -6;
  is $app1->recache->overload(1)->array2(3..6)->[0], -6;
  my $overload1 = $app1->recache->overload(1)->array2(3..6);
  is $overload1->[0], -6;
  is $$overload1->data->[0], -6;
  is $$overload1->cached, 1;
  my $normal1 = $app1->recache->array2(4..6);
  is $normal1->data->[0], -8;
  is $normal1->cached, 0;
  is $app1->recache->array2(4..6)->cached, 1;
  is $app1->recache->overload(1)->array(3..6)->[0], -6;
};

Mojo::Recache->new->home->tap(sub{$_->remove_tree if $_->basename eq 'recache'});
done_testing;
