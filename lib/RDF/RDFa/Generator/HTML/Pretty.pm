package RDF::RDFa::Generator::HTML::Pretty;

use 5.008;
use base qw'RDF::RDFa::Generator::HTML::Hidden';
use strict;
use constant XHTML_NS => 'http://www.w3.org/1999/xhtml';
use Encode qw'encode_utf8';
use Icon::FamFamFam::Silk;
use RDF::RDFa::Generator::HTML::Pretty::Note;
use XML::LibXML qw':all';

use warnings;


our $VERSION = '0.201_01';

sub create_document
{
	my ($proto, $model, %opts) = @_;
	my $self = (ref $proto) ? $proto : $proto->new;
	
	my $html = sprintf(<<HTML, ($self->{'version'}||'1.0'), ($self->{'title'} || 'RDFa Document'), ref $self);
<html xmlns="http://www.w3.org/1999/xhtml" version="XHTML+RDFa %1\$s">
<head profile="http://www.w3.org/1999/xhtml/vocab">
<title>%2\$s</title>
<meta name="generator" value="%3\$s" />
</head>
<body>
<h1>%2\$s</h1>
<main/>
<footer>
<p><small>Generated by %3\$s.</small></p>
</footer>
</body>
</html>
HTML

	return $proto->inject_document($html, $model, %opts);
}

sub injection_site
{
	return '//xhtml:main';
}


sub nodes
{
	my ($proto, $model, %opts) = @_;
	my $self = (ref $proto) ? $proto : $proto->new;
	
	my $stream = $self->_get_stream($model);
	my @nodes;
	
	my $root_node = XML::LibXML::Element->new('div');
	$root_node->setNamespace(XHTML_NS, undef, 1);
	
	my $subjects = {};
	while (my $st = $stream->next)
	{
		next if $st->subject->is_literal;  # ???
		my $s = $st->subject->is_resource ?
			$st->subject->abs :
			('_:'.$st->subject->value);
		push @{ $subjects->{$s} }, $st;
	}
	
	foreach my $s (sort keys %$subjects)
	{
		my $subject_node = $root_node->addNewChild(XHTML_NS, 'div');
		
		my $id = _make_id($s, $opts{'id_prefix'});
		$subject_node->setAttribute('id', $id) if defined $id;
		
		$self->_process_subject($subjects->{$s}->[0], $subject_node);
		$self->_resource_heading($subjects->{$s}->[0]->subject, $subject_node, $subjects->{$s});
		$self->_resource_classes($subjects->{$s}->[0]->subject, $subject_node, $subjects->{$s});
		$self->_resource_statements($subjects->{$s}->[0]->subject, $subject_node, $subjects->{$s}, $opts{'interlink'}||0, $opts{'id_prefix'}, $model);
		$self->_resource_notes($subjects->{$s}->[0]->subject, $subject_node, $model, $opts{'notes_heading'}||'Notes', $opts{'notes'})
			if defined $opts{'notes'};
	}

	if (defined($self->{'version'}) && $self->{'version'} == 1.1
	and $self->{'prefix_attr'})
	{
	  if (defined($self->{namespacemap}->rdfa)) {
		 $root_node->setAttribute('prefix', $self->{namespacemap}->rdfa->as_string)
	  }
	}
	else
	{
	  while (my ($prefix, $nsURI) = $self->{namespacemap}->each_map) {
		 $root_node->setNamespace($nsURI->as_string, $prefix, 0);
	  }
	}
	
	push @nodes, $root_node;
	return @nodes if wantarray;
	my $nodelist = XML::LibXML::NodeList->new;
	$nodelist->push(@nodes);
	return $nodelist;
}

sub _make_id
{
	my ($ident, $prefix) = @_;
	
	if (defined($prefix) && ($prefix =~ /^[A-Za-z][A-Za-z0-9\_\:\.\-]*$/))
	{
		$ident =~ s/([^A-Za-z0-9\_\:\.])/sprintf('-%x-',ord($1))/ge;
		return $prefix . $ident;
	}
	
	return undef;
}

sub _resource_heading
{
	my ($self, $subject, $node, $statements) = @_;
	
	my $heading = $node->addNewChild(XHTML_NS, 'h3');
	$heading->appendTextNode( $subject->is_resource ? $subject->abs : ('_:'.$subject->value) );
	$heading->setAttribute('class', $subject->is_resource ? 'resource' : 'blank' );
	
	return $self;
}

sub _resource_classes
{
	my ($self, $subject, $node, $statements) = @_;
	
	my @statements = sort {
		$a->predicate->abs cmp $b->predicate->abs
		or $a->object->abs cmp $b->object->abs
		}
		grep {
			$_->predicate->abs eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
			and $_->object->is_resource
		}
		@$statements;

	return unless @statements;

	my $SPAN = $node->addNewChild(XHTML_NS, 'span');
	$SPAN->setAttribute('class', 'rdf-type');
	$SPAN->setAttribute('rel', $self->_make_curie('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'));

	foreach my $st (@statements)
	{
		my $IMG = $SPAN->addNewChild(XHTML_NS, 'img');
		$IMG->setAttribute('about', $st->object->abs);
		$IMG->setAttribute('alt',   $st->object->abs);
		$IMG->setAttribute('src',   $self->_img($st->object->abs));
		$IMG->setAttribute('title', $st->object->abs);
	}

	return $self;
}


sub _resource_statements
{
	my ($self, $subject, $node, $statements, $interlink, $id_prefix, $model) = @_;
	
	my @statements = sort {
		$a->predicate->abs cmp $b->predicate->abs
		or $a->object->ntriples_string cmp $b->object->ntriples_string
		}
		grep {
			$_->predicate->abs ne 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
			or !$_->object->is_resource
		}
		@$statements;

	return unless @statements;
	
	my $DL = $node->addNewChild(XHTML_NS, 'dl');
	
	my $current_property = undef;
	foreach my $st (@statements)
	{
		unless (defined($current_property) && ($st->predicate->abs eq $current_property))
		{
			my $DT = $DL->addNewChild(XHTML_NS, 'dt');
			$DT->setAttribute('title', $st->predicate->abs);
			$DT->appendTextNode($self->_make_curie($st->predicate));
		}
		$current_property = $st->predicate->abs;
		
		my $DD = $DL->addNewChild(XHTML_NS, 'dd');
		
		if ($st->object->is_resource && $st->object->abs =~ /^javascript:/i)
		{
			$DD->setAttribute('class', 'resource');
			
			my $A = $DD->addNewChild(XHTML_NS, 'span');
			$A->setAttribute('rel',  $self->_make_curie($st->predicate));
			$A->setAttribute('resource', $st->object->abs);
			$A->appendTextNode($st->object->abs);
		}
		elsif ($st->object->is_resource)
		{
			$DD->setAttribute('class', 'resource');
			
			my $A = $DD->addNewChild(XHTML_NS, 'a');
			$A->setAttribute('rel',  $self->_make_curie($st->predicate));
			$A->setAttribute('href', $st->object->abs);
			$A->appendTextNode($st->object->abs);			
		}
		elsif ($st->object->is_blank)
		{
			$DD->setAttribute('class', 'blank');
			
			my $A = $DD->addNewChild(XHTML_NS, 'span');
			$A->setAttribute('rel',  $self->_make_curie($st->predicate));
			$A->setAttribute('resource', '[_:'.$st->object->value.']');
			$A->appendTextNode('_:'.$st->object->value);
		}
		elsif ($self->{'safe_xml_literals'}
		&& $st->object->is_literal
		&& $st->object->datatype->value eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral')
		{
			$DD->setAttribute('property',  $self->_make_curie($st->predicate));
			$DD->setAttribute('class', 'typed-literal datatype-xmlliteral');
			$DD->setAttribute('datatype',  $self->_make_curie($st->object->datatype));
			$DD->setAttribute('content', encode_utf8($st->object->value));
			$DD->addNewChild(XHTML_NS, 'pre')->addNewChild(XHTML_NS, 'code')->appendTextNode(encode_utf8($st->object->value));
		}
		elsif ($st->object->is_literal
		&& $st->object->datatype->value eq 'http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral')
		{
			$DD->setAttribute('property',  $self->_make_curie($st->predicate));
			$DD->setAttribute('class', 'typed-literal datatype-xmlliteral');
			$DD->setAttribute('datatype',  $self->_make_curie($st->object->datatype));
			$DD->appendWellBalancedChunk(encode_utf8($st->object->value));
		}
		elsif ($st->object->is_literal)
		{
			$DD->setAttribute('property',  $self->_make_curie($st->predicate));
			$DD->setAttribute('class', 'typed-literal');
			if ($st->object->has_language) {
			  $DD->setAttribute('xml:lang',  ''.$st->object->language);
			}
			$DD->setAttribute('datatype',  $self->_make_curie($st->object->datatype));
			$DD->appendTextNode(encode_utf8($st->object->value));
		}

		if ($interlink && !$st->object->is_literal)
		{
			if ($model->count_quads($st->object, undef, undef, undef))
			{
				$DD->appendTextNode(' ');
				my $seealso = $DD->addNewChild(XHTML_NS, 'a');
				$seealso->setAttribute('about', $st->object->is_resource ? $st->object->abs : '[_:'.$st->object->value.']');
				$seealso->setAttribute('rel', $self->_make_curie('http://www.w3.org/2000/01/rdf-schema#seeAlso'));
				$seealso->setAttribute('href', '#'._make_id($st->object->is_resource ? $st->object->abs : '_:'.$st->object->value, $id_prefix));
				$seealso->appendTextNode($interlink);
			}
		}
	}
	
	if ($interlink)
	{
		my $iter = $model->get_quads(undef, undef, $subject, undef)->materialize;
		if ($iter->peek)
		{
			my $seealsoDT = $DL->addNewChild(XHTML_NS, 'dt');
			$seealsoDT->setAttribute('class', 'seeAlso');
			$seealsoDT->appendTextNode($interlink);

			my $sadata = {};
			while (my $sast = $iter->next)
			{
				my $sas = $sast->subject->is_resource ? $sast->subject->abs : '_:'.$sast->subject->value;
				my $p = $self->_make_curie($sast->predicate);
				$sadata->{$sas}->{$p} = $sast->predicate->abs;
			}
			
			my $seealso = $DL->addNewChild(XHTML_NS, 'dd');
			$seealso->setAttribute('class', 'seeAlso');
			my @keys = sort keys %$sadata;
			foreach my $sas (@keys)
			{
				my $span = $seealso->addNewChild(XHTML_NS, 'span');
				$span->appendTextNode('is ');
				my @pkeys = sort keys %{$sadata->{$sas}};
				foreach my $curie (@pkeys)
				{
					my $i = $span->addNewChild(XHTML_NS, 'i');
					$i->appendTextNode($curie);
					$i->setAttribute(title => $sadata->{$sas}->{$curie});
					$span->appendTextNode( $curie eq $pkeys[-1] ? '' : ', ' );
				}
				$span->appendTextNode(' of ');
				my $a = $span->addNewChild(XHTML_NS, 'a');
				$a->setAttribute('about', $sas !~ /^_:/ ? $sas : '[_:'.$sas.']');
				$a->setAttribute('rel', $self->_make_curie('http://www.w3.org/2000/01/rdf-schema#seeAlso'));
				$a->setAttribute('href', '#'._make_id($sas, $id_prefix));
				$a->appendTextNode($sas);
				$seealso->appendTextNode( $sas eq $keys[-1] ? '.' : '; ' );
			}
		}
	}
	
	return $self;
}

sub _resource_notes
{
	my ($self, $subject, $node, $model, $notes_heading, $notes) = @_;
	
	my @relevant;
	
	foreach my $note (@$notes)
	{
		push @relevant, $note
			if $note->is_relevant_to($subject);
	}
	
	if (@relevant) {
		my $wrapper = $node->addNewChild(XHTML_NS, 'aside');
		my $heading = $wrapper->addNewChild(XHTML_NS, 'h4');
		$heading->appendTextNode($notes_heading || 'Notes');

		my $list = $wrapper->addNewChild(XHTML_NS, 'ul');

		foreach my $note (@relevant)
		{
			$list->appendChild( $note->node(XHTML_NS, 'li') );
		}
	}
	
	return $self;
}

sub _img
{
	my ($self, $type) = @_;
	
	if ($type eq 'urn:x-rdf-rdfa-linter:internals:OpenGraphProtocolNode')
	{
		return 'data:image/png;charset=binary;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAAXNSR0IArs4c6QAAAAlwSFlzAAALEwAACxMBAJqcGAAAAAd0SU1FB9oFEBYGBzcdoOEAAALhSURBVCjPJdLfb4trHADw7/d53nbr2661X9ZV29mE/VLMYplwchwnmCziR7iSEHbpQnAj7lxJJBIhJELcSBAh50iErAcJ2wnLRrJstQXdL7Sbtmpv173P3vd9nq8Ln7/hg3/t6BJCAEB9Q/2Na1d8Xt1YmsuaSVsKn7u6Sl/lZjoAIiIAEJG2aJpSyi2dnceOH87I4UfD12fyw7aJ0mIu3fHqZbHa7s4VxwLuECJDRA0Bund3vXz1cmWCjMyzz33uz31e4zsCANcg2Kimtz8Ya32xv+VC1N/BkPM//tzW03MEArN3b/1X6vJ8G+VKYmWUwjEyC8A0TPa7hVjMlsUbKjf7S2r4m//7YVl6sHB56q1uzGJkPYkC1HdQrEulxrAiAkgwMaC5y5ac6kRrdbfm83kfj9yYGtK4BvUdKhFnjENmEhbnubQwEcdwTK3rVh96S0KxkanIG61o56fyQzNDnrU7VfPf0jQwO4luDy1kcVmI5mehba8Mr6Ovw2wuoY83xrW8mHEslf+KP9P4/l+emUQ9QBURUJJsAVzDj694bpqQQW6GZcykJpUgQMeC+TQgQ2GAcjA1BqBAOuDYkE+hJcAyQdoglaWVuYPIHV8l1bVTzRo18pRbJoRalFVEZJCbxtadMhyj3kuat1L5Sqo1f0ltuR6qaTRSH7C2BQpZNGbBsTgiWSYW81j8gQs5MjK44YAT9W9iHF0bQwcbti6kEqzvJrcFlAagrl1tOSq95RQI0qd+9uKqFmpWVVG+KXyIAWBb8FBT0+rYHpGbZv7l5KugQgYKGSzmMdhITduULUDSUlfzmYf34khERJQujj4YPTk+mB154jHm0OUh7oKlAgKDtr2yPCpe34YTPacGBt4hEf1umBMTzycvJr68zk2UZpPMsdBbTsEWq2pF6a7m02ay7uy587Zto1Lqd10AcJSVLo6OZ3u/L35ylPC5qiL+9rbQvn8ePr9z9346lXKk/AUjmnS/afx+BwAAAABJRU5ErkJggg==';
	}
	
	my $icons = {
		'http://bblfish.net/work/atom-owl/2006-06-06/#Entry'   => 'page_white_link',
		'http://bblfish.net/work/atom-owl/2006-06-06/#Feed'    => 'feed',
		'http://commontag.org/ns#AuthorTag'                    => 'tag_green',
		'http://commontag.org/ns#AutoTag'                      => 'tag_red',
		'http://commontag.org/ns#ReaderTag'                    => 'tag_yellow',
		'http://commontag.org/ns#Tag'                          => 'tag_blue',
		'http://ontologi.es/doap-bugs#Bug'                     => 'bug',
		'http://purl.org/goodrelations/v1#PriceSpecification'  => 'money',
		'http://purl.org/NET/book/vocab#Book'                  => 'book',
		'http://purl.org/NET/c4dm/event.owl#Event'             => 'date',
		'http://purl.org/ontology/bibo/Book'                   => 'book',
		'http://purl.org/rss/1.0/channel'                      => 'feed',
		'http://purl.org/rss/1.0/item'                         => 'page_white_link' ,
		'http://purl.org/stuff/rev#Review'                     => 'award_star_gold_1',
		'http://rdf.data-vocabulary.org/#Organization'         => 'chart_organisation',
		'http://rdf.data-vocabulary.org/#Person'               => 'user',
		'http://rdf.data-vocabulary.org/#Review-aggregate'     => 'award_star_add',
		'http://rdf.data-vocabulary.org/#Review'               => 'award_star_gold_1',
		'http://schema.org/Person'                             => 'user_orange',
		'http://schema.org/Event'                              => 'date',
		'http://schema.org/FinancialService'                   => 'money',
		'http://schema.org/TennisComplex'                      => 'sport_tennis',
		'http://schema.org/Bakery'                             => 'cake',
		'http://schema.org/Map'                                => 'world',
		'http://schema.org/GolfClub'                           => 'sport_golf',
		'http://schema.org/CafeOrCoffeeShop'                   => 'cup',
		'http://schema.org/ProfilePage'                        => 'page_green',
		'http://usefulinc.com/ns/doap#Project'                 => 'application_double',
		'http://usefulinc.com/ns/doap#Version'                 => 'application_lightning',
		'http://www.holygoat.co.uk/owl/redwood/0.1/tags/Tagging' => 'tag_blue_add',
		'http://www.holygoat.co.uk/owl/redwood/0.1/tags/Tag'   => 'tag_blue',
		'http://www.w3.org/1999/02/22-rdf-syntax-ns#Property'  => 'arrow_right',
		'http://www.w3.org/2000/01/rdf-schema#Class'           => 'cog',
		'http://www.w3.org/2002/12/cal/ical#Vcalendar'         => 'calendar',
		'http://www.w3.org/2002/12/cal/ical#Vevent'            => 'date',
		'http://www.w3.org/2002/07/owl#AnnotationProperty'     => 'arrow_right',
		'http://www.w3.org/2002/07/owl#AsymmetricProperty'     => 'arrow_right',
		'http://www.w3.org/2002/07/owl#Class'                  => 'cog',
		'http://www.w3.org/2002/07/owl#DatatypeProperty'       => 'arrow_right',
		'http://www.w3.org/2002/07/owl#DeprecatedProperty'     => 'arrow_right',
		'http://www.w3.org/2002/07/owl#FunctionalProperty'     => 'arrow_right',
		'http://www.w3.org/2002/07/owl#InverseFunctionalProperty' => 'arrow_right',
		'http://www.w3.org/2002/07/owl#IrreflexiveProperty'    => 'arrow_right',
		'http://www.w3.org/2002/07/owl#ObjectProperty'         => 'arrow_right',
		'http://www.w3.org/2002/07/owl#OntologyProperty'       => 'arrow_right',
		'http://www.w3.org/2002/07/owl#ReflexiveProperty'      => 'arrow_right',
		'http://www.w3.org/2002/07/owl#SymmetricProperty'      => 'arrow_right',
		'http://www.w3.org/2002/07/owl#TransitiveProperty'     => 'arrow_right',
		'http://www.w3.org/2003/01/geo/wgs84_pos#Point'        => 'world', 
		'http://www.w3.org/2003/01/geo/wgs84_pos#SpatialThing' => 'world',
		'http://www.w3.org/2004/02/skos/core#Concept'          => 'brick',
		'http://www.w3.org/2004/02/skos/core#ConceptScheme'    => 'bricks',
		'http://www.w3.org/2006/vcard/ns#Address'              => 'house',
		'http://www.w3.org/2006/vcard/ns#Location'             => 'world', 
		'http://www.w3.org/2006/vcard/ns#Vcard'                => 'vcard',
		'http://www.w3.org/ns/auth/rsa#RSAPublicKey'           => 'key',
		'http://xmlns.com/foaf/0.1/Agent'                      => 'user_gray',
		'http://xmlns.com/foaf/0.1/Document'                   => 'page_white_text',
		'http://xmlns.com/foaf/0.1/Group'                      => 'group',
		'http://xmlns.com/foaf/0.1/Image'                      => 'image',
		'http://xmlns.com/foaf/0.1/OnlineAccount'              => 'status_online',
		'http://xmlns.com/foaf/0.1/Organization'               => 'chart_organisation',
		'http://xmlns.com/foaf/0.1/Person'                     => 'user_green',
		'http://xmlns.com/foaf/0.1/PersonalProfileDocument'    => 'page_green',
	};
	
	return Icon::FamFamFam::Silk->new($icons->{$type}||'asterisk_yellow')->uri;
}

1;
