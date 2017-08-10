#!/usr/bin/perl

# tests from KjetilK

use strict;
use Test::More;

use RDF::Trine::Model;

my $model = RDF::Trine::Model->temporary_model;

use RDF::Trine::Parser;
my $parser     = RDF::Trine::Parser->new( 'turtle' );
$parser->parse_into_model( 'http://example.org/', '</foo> a </Bar> .', $model );

use RDF::RDFa::Generator;

{
	ok(my $document = RDF::RDFa::Generator->new->create_document($model), 'Assignment OK');
	isa_ok($document, 'XML::LibXML::Document');
	my $string = $document->toString;

	like($string, qr|about="http://example.org/foo"|, 'Subject URI present');
	like($string, qr|rel="rdf:type"|, 'Type predicate present');
	like($string, qr|resource="http://example.org/Bar"|, 'Object present');
}

done_testing();
