# -*- coding: utf-8 -*-
module ClayText
  # These are the values that Paragraph.type can take
  PARAGRAPH_TYPES = %i[plain ulitem olitem subheading header footer]

  # see: http://php.net/manual/en/function.htmlspecialchars.php
  HTMLESCAPE_RULES = {
    '&' => '&amp;',
    '"' => '&quot;',
    "'" => '&#39;',
    '<' => '&lt;',
    '>' => '&gt;'
  }

  # Key is used to match each line in a paragraph, and value is the
  # lambda that'll act on the matched paragraph.
  PARAGRAPH_LINE_FILTERS = {
    # If all the lines in a paragraph begin with "\d+\. ", those three
    # characters are stripped from the content, and the paragraph is
    # marked as an :olitem,
    proc { |line| line.start_with? "\d+\. " } => lambda do |paragraph|
      paragraph.contents.map! { |l| [3..-1].rstrip }
      paragraph.type = :olitem
    end,

    # If all the lines in a paragraph begin with "- ", those two
    # characters are stripped from the content, and the paragraph is
    # marked as an :ulitem.
    proc { |line| line.start_with? "- " } => lambda do |paragraph|
      paragraph.contents.map! { |l| l[2..-1].rstrip }
      paragraph.type = :ulitem
    end,

    # If all the lines in a paragraph begin with '[\d+]: ', the
    # paragraph is marked as :footer.  Also, a regex substitution runs
    # on each line turning every link like http://url-over-33-chars to
    # <a href="http://google.com">30-characters-of-the-li...</a>
    # Also, special case github.com links.
    proc { |line| /^\[\d+\]: / =~ line } => lambda do |paragraph|
      paragraph.type = :footer
      paragraph.contents.map { |k| k.gsub!(%r{^(\[\d+\]:) (.*://(.*))}) do
          if $3.start_with? 'github.com'
            text = 'gh:' + $3[11, 30]
            trunc_len = 44 # 33 + 11
          else
            text = $3[0, 30]
            trunc_len = 33 # 33 = 30 + "...".size
          end
          "#{$1} <a href=\"#{$2}\">#{text}#{%{...} if $3.length > trunc_len}</a>"
        end
      }
    end
  }

  # A paragraph of text
  #
  # :content contains its content
  # :type can be one of PARAGRAPH_TYPES
  # :level is an integer which has a type-specific meaning
  class Paragraph
    attr_accessor :contents, :type

    def initialize contents
      @contents = contents
      @type = :plain

      # Generate is_*? methods for PARAGRAPH_TYPES
      Paragraph.class_eval do
        ClayText::PARAGRAPH_TYPES.each do |type|
          define_method("is_#{type.to_s}?") { @type == type }
        end
      end
    end
  end

  # Takes a body of claytext, breaks it up into paragraphs, and
  # applies various rules on it.
  #
  # Returns a list of Paragraphs
  def self.process body
    # First, htmlescape the body text
    body.gsub! /[&"'<>]/, ClayText::HTMLESCAPE_RULES

    # Split the body into Paragraphs
    paragraphs = []
    body.split("\n\n").each do |content|
      paragraphs << Paragraph.new(content.lines.map! { |l| l.strip })
    end

    # Special matching for the first paragraph.  This paragraph will
    # be marked header:
    #
    # (This is a really long first paragraph blah-blah-blah-blah-blah
    # that spans to two lines)
    if paragraphs[0].contents.size == 1 and
       paragraphs[0].contents[0].start_with? '(' and
       paragraphs[0].contents[0].end_with? ')'
      paragraphs[0].type = :header
    end

    paragraphs.each do |paragraph|
      # Apply the PARAGRAPH_LINE_FILTERS on all the paragraphs
      ClayText::PARAGRAPH_LINE_FILTERS.each do |proc_match, lambda_cb|
        if paragraph.contents.all? &proc_match
          lambda_cb.call paragraph
        end
      end
    end

    paragraphs
  end
end
