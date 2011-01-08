#!perl
#
# This file is part of AnyEvent-Worker-DynamicPool
#
# This software is copyright (c) 2011 by Brian Phillips.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#

use Test::More;

eval "use Test::CPAN::Meta";
plan skip_all => "Test::CPAN::Meta required for testing META.yml" if $@;
meta_yaml_ok();
