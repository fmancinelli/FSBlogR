#!/usr/bin/ruby

# FSBlogR - A compact, self contained, file-system oriented blogging system
# Copyright (C) 2009 Fabio Mancinelli <fm@fabiomancinelli.org>
# 
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
# 
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Library General Public License for more details.
# 
# You should have received a copy of the GNU Library General Public
# License along with this library; if not, write to the Free
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require 'cgi'
require 'find'
require 'erb'

##############################################################################
# Configuration
##############################################################################
if File.exists?('fsblogr-conf.rb')
  require 'fsblogr-conf.rb'
else
  $blog_title = ""
  $blog_data_directory = ""
  $blog_templates_directory = ""
  $blog_post_extension = ".blog"
  $blog_page_extension = ".page"
  $blog_posts_per_page = 4
end

##############################################################################
# Initialize defaults
##############################################################################
$blog_post_extension = ".blog" if $blog_post_extension == nil
$blog_page_extension = ".page" if $blog_page_extension == nil
$blog_posts_per_page = 4 if $blog_posts_per_page == nil

##############################################################################
# Default html templates
##############################################################################
$default_html_header_template = <<-END_OF_STRING
<html>
  <body>
END_OF_STRING

$default_html_blog_post_template = <<-END_OF_STRING
<h1><%= title %></h1><%= content %><hr/>
END_OF_STRING

$default_html_blog_post_single_template = <<-END_OF_STRING
<h1>Single : <%= title %></h1><%= content %><hr/>
END_OF_STRING

$default_html_page_template = <<-END_OF_STRING
<h1>Page : <%= title %></h1><%= content %><hr/>
END_OF_STRING

$default_html_footer_template = <<-END_OF_STRING
</body>
END_OF_STRING

$default_html_not_found_template = <<-END_OF_STRING
<h1>Not found</h1>
END_OF_STRING

##############################################################################
# Default atom templates
##############################################################################
$default_atom_header_template = <<-END_OF_STRING
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title><%= blog_title %></title>
  <updated><%= last_update_time.strftime("%Y-%m-%dT%H:%M:%S") %></updated>
  <author>
    <name><%= blog_title %></name>
  </author>
  <id><%= blog_title %></id>
END_OF_STRING

$default_atom_blog_post_template = <<-END_OF_STRING
  <entry>
    <title><%= title %></title>
    <link href="<%= permalink %>"/>
    <id><%= permalink %></id>
    <updated><%= time.strftime("%Y-%m-%dT%H:%M:%S") %></updated>
    <content type="html">
      <%= content %>
    </content>
  </entry>
END_OF_STRING

$default_atom_footer_template = <<-END_OF_STRING
</feed>
END_OF_STRING

##############################################################################
# Functions
##############################################################################
def get_uri_path(local_path)
  # Clean duplicated /, remove extension and trailing ///
  result = local_path.sub($blog_data_directory, "").squeeze("/").sub(/\..*/, "").sub(/\/+$/, "")
  if result == ""
    result = "/"
  end
  
  result
end

def get_type(local_path)
  if !FileTest.exists?(local_path)
    return nil  
  elsif FileTest.directory?(local_path)
    return :category    
  elsif File.extname(local_path) == $blog_post_extension
    return :blog_post
  elsif File.extname(local_path) == $blog_page_extension
    return :page
  end
  
  nil
end

def parse_blog_post_or_page_content(local_path)
  if !FileTest.file?(local_path)
    return nil
  end

  # The category is given by the directory path in which the post is located
  category = File.dirname(local_path.sub($blog_data_directory, "")).squeeze("/")
  if category =~ /\/$/
    category.chomp("/")
  end
  
  # The file name giving the post name
  name = File.basename(local_path, File.extname(local_path))

  # Read all the lines from the file
  lines = IO.readlines(local_path)
  
  # Check if data is there
  if lines.length < 2
    return nil
  end

  # Scan for metadata
  i = 0
  time = File.mtime(local_path)
  tags = []
  lines.each do |line|
    # Metadata ends at the first line that doesn't begin with a #
    if line !~ /^#/
      break
    end

    if match = /^#tags:/.match(line)
      # Parse the tags metadata
      tags = match.post_match.strip.split(",")
    end

    i = i + 1
  end

  # The title is the first line after the metadata
  title = lines[i].strip
  # The post content is the remaining text
  content = lines[i+1, lines.length].join.strip
  
  {:uri_path => get_uri_path(local_path), :name => name, :title => title, :time => time, :content => content, :category => category, :tags => tags}
end

def parse_blog_post(local_path)
  result = parse_blog_post_or_page_content(local_path)
  result[:type] = :blog_post
  
  result
end

def parse_page(local_path)
  result = parse_blog_post_or_page_content(local_path)
  result[:type] = :page
  
  result
end

def parse_entity(local_path)
  type = get_type(local_path)
  
  result = case get_type(local_path)
    when :blog_post then parse_blog_post(local_path)
    when :page then parse_page(local_path)
    when :category then 
      uri_path = get_uri_path(local_path)
      {:type => :category, :uri_path => uri_path, :name => uri_path}
    else nil
  end
  
  result  
end

def parse_uri_path(uri_path)
  uri_path_segments = uri_path.split(";", 2)  
  
  date_filter = {}
  tags_filter = []
  blog_path = ""

  if uri_path_segments[1] != nil
    tags_filter = uri_path_segments[1].split(",")
  end

  if match = /\/(\d\d\d\d)\/(\d\d)\/(\d\d)/.match(uri_path_segments[0])
    date_filter[:year] = match[1]
    date_filter[:month] = match[2]
    date_filter[:day] = match[3]
    blog_path = match.post_match
  elsif match = /\/(\d\d\d\d)\/(\d\d)/.match(uri_path_segments[0])
    date_filter[:year] = match[1]
    date_filter[:month] = match[2]
    blog_path = match.post_match
  elsif match = /\/(\d\d\d\d)/.match(uri_path_segments[0])
    date_filter[:year] = match[1]
    blog_path = match.post_match
  elsif  
    blog_path = uri_path_segments[0]  
  end

  return blog_path, date_filter, tags_filter
end

def accept_entity?(entity, date_filter, tags_filter)
  if date_filter[:year] != nil && entity[:time].year.to_s != date_filter[:year]
    return false
  end
  
  if date_filter[:month] != nil && entity[:time].month.to_s != date_filter[:month]
    return false
  end
  
  if date_filter[:day] != nil && entity[:time].day.to_s != date_filter[:day]
    return false
  end
  
  if tags_filter != [] && entity[:tags] & tags_filter == []
    return false
  end

  return true
end

def find_entity(entities, uri_path)
  # Clean duplicated / and remove trailing ///
  uri_path = uri_path.squeeze("/").sub(/\/+$/, "")
  
  # Find a match for the uri_path
  entities.each do |entity|
    if entity[:uri_path] =~ /^#{uri_path}\/?$/
      return entity
    end
  end
  
  nil
end

def find_entities(entities, category = :all, type = :all)
  result = []
  entities.each do |entity|
    if category == :all || entity[:category] =~ /^#{category}/
      if type == :all || entity[:type] == type
        result.push(entity)
      end
    end
  end
  
  result
end

# This is meta programming magic. Create a binding containing a set of variables with the names taken from hash keys, 
# and assign to them the corresponding values in the hash.
def create_binding(variable_to_value_hash)  
  current_binding = binding
  for variable in variable_to_value_hash.keys
    eval "#{variable.to_s} = variable_to_value_hash[variable]", binding
    current_binding = binding
  end
  current_binding
end

def get_permalink(entity)
  "#{$blog_base_uri}#{entity[:uri_path]}"
end

def apply_plugins(format, content, plugins)
  plugins.each do |plugin|
    content = eval "#{plugin}(format, content)"
  end
  
  content
end

def load_template(format)
  template = Hash.new

  # Fill defaults if format is html
  if format == "html"
    template[:content_type] = "text/html"
    template[:header] = ERB.new($default_html_header_template)
    template[:blog_post] = ERB.new($default_html_blog_post_template)
    template[:blog_post_single] = ERB.new($default_html_blog_post_single_template)
    template[:page] = ERB.new($default_html_page_template)
    template[:not_found] = ERB.new($default_html_not_found_template)
    template[:footer] = ERB.new($default_html_footer_template)
  elsif format == "atom"
    template[:content_type] = "application/atom+xml"    
    template[:header] = ERB.new($default_atom_header_template)
    template[:blog_post] = ERB.new($default_atom_blog_post_template)
    template[:blog_post_single] = ERB.new($default_atom_blog_post_template)
    template[:page] = ERB.new($default_atom_blog_post_template)
    template[:not_found] = ERB.new("")
    template[:footer] = ERB.new($default_atom_footer_template)
  end

  content_type_template_file = File.join($blog_templates_directory, format, "content_type")
  header_template_file = File.join($blog_templates_directory, format, "header")
  blog_post_template_file = File.join($blog_templates_directory, format, "blog_post")
  blog_post_single_template_file = File.join($blog_templates_directory, format, "blog_post_single")
  page_template_file = File.join($blog_templates_directory, format, "page")
  not_found_template_file = File.join($blog_templates_directory, format, "not_found")
  footer_template_file = File.join($blog_templates_directory, format, "footer")

  template[:content_type] = IO.read(content_type_template_file) if File.exists?(content_type_template_file)
  template[:header] = ERB.new(IO.read(header_template_file)) if File.exists?(header_template_file)
  template[:blog_post] = ERB.new(IO.read(blog_post_template_file)) if File.exists?(blog_post_template_file)
  template[:blog_post_single] = ERB.new(IO.read(blog_post_single_template_file)) if File.exists?(blog_post_single_template_file)
  template[:page] = ERB.new(IO.read(page_template_file)) if File.exists?(page_template_file)
  template[:not_found] = ERB.new(IO.read(not_found_template_file)) if File.exists?(not_found_template_file)
  template[:footer] = ERB.new(IO.read(footer_template_file)) if File.exists?(footer_template_file)

  if template[:content_type] == nil || template[:header] == nil || template[:blog_post] == nil || template[:blog_post_single] == nil || template[:not_found] == nil || template[:footer] == nil
    return nil
  end
  
  template
end

def render(uri_path, entities, format, page, header_footer_variables, date_filter = {}, tags_filter = [], plugins = [])
  # Load templates
  template = load_template(format)
  
  # Find the entity the uri_path refers to in order to understand how to do the rendering
  entity = find_entity(entities, uri_path)

  # This variable will keep the rendering of the blog posts part
  main_content = ""
  
  # The following variables are to be used in the header/footer and they depend on the rendered posts
  # Initialize to default values
  last_update_time = Time.now
  header_footer_variables[:previous_page_link] = nil
  header_footer_variables[:next_page_link] = nil
  
  # If the uri_path doesn't reference any entity, then render the :not_found template
  if entity == nil
    main_content << template[:not_found].result(create_binding(header_footer_variables))
  else
    case entity[:type]
    when :blog_post
      # If the uri_path references a precise blog post, render it using the :blog_post_single template
      entity[:base_uri] = $blog_base_uri
      entity[:permalink] = get_permalink(entity)
      
      # Apply plugins
      entity[:content] = apply_plugins(format, entity[:content], plugins)
      
      # Check if the entity matches with the filters
      if accept_entity?(entity, date_filter, tags_filter)
        main_content << template[:blog_post_single].result(create_binding(entity))
      else
        main_content << template[:not_found].result(create_binding(header_footer_variables))
      end
    when :page
      # If the uri_path references a page, render it using the :page template
      entity[:base_uri] = $blog_base_uri
      entity[:permalink] = get_permalink(entity)

      # Apply plugins
      entity[:content] = apply_plugins(format, entity[:content], plugins)
      
      # Check if the entity matches with the filters
      if accept_entity?(entity, date_filter, tags_filter)
        main_content << template[:page].result(create_binding(entity))
      else
        main_content << template[:not_found].result(create_binding(header_footer_variables))
      end
      
    when :category
      # If the uri_path references a category, render all the blog posts in it taking into account pagination information and filters
      blog_posts = find_entities(entities, entity[:name], :blog_post)
      
      filtered_posts = []
      blog_posts.each do |post|
        if accept_entity?(post, date_filter, tags_filter)
          filtered_posts.push(post)
        end
      end
      
      # If there are posts in the final array, render them
      if filtered_posts.length != 0
        # Sort the collected posts by time, reverse
        filtered_posts.sort! {|x,y| y[:time] <=> x[:time]}

        header_footer_variables[:last_update_time] = filtered_posts[0][:time]
        
      
        # Render the posts collection
        0.upto($blog_posts_per_page - 1) {|i|
          post = filtered_posts[page * $blog_posts_per_page + i]
          if post != nil
            post[:base_uri] = $blog_base_uri
            post[:permalink] = get_permalink(post)
            
            # Apply plugins
            post[:content] = apply_plugins(format, post[:content], plugins)
            
            main_content << template[:blog_post].result(create_binding(post))
          end
        }

        # Compute previous and next page links
        current_uri = "#{$blog_base_uri}#{uri_path}"

        if page > 0
          header_footer_variables[:next_page_link] = "#{current_uri}?page=#{page - 1}"
        end

        if filtered_posts[(page + 1) * $blog_posts_per_page] != nil
          header_footer_variables[:previous_page_link] = "#{current_uri}?page=#{page + 1}"
        end
      else
        # If there a no posts in the filtered result then render the :not_found template
        main_content << template[:not_found].result(create_binding(header_footer_variables))
      end
    end
  end
    
  result = ""
  result << "Content-type: #{template[:content_type]}\n\n"
  result << template[:header].result(create_binding(header_footer_variables))
  result << main_content
  result << template[:footer].result(create_binding(header_footer_variables))
  
  result
end

def get_categories_info(entities)
  result = Hash.new
  entities.each do |entity|
    if entity[:type] == :blog_post
      if result[entity[:category]] == nil
        result[entity[:category]] = { :link => "#{$blog_base_uri}#{entity[:category]}", :posts => []}
      end
      result[entity[:category]][:posts].push(entity)
    end
  end

  result
end

def get_pages(entities)
  result = []
  entities.each do |entity|
    if entity[:type] == :page
      entity[:base_uri] = $blog_base_uri
      entity[:permalink] = get_permalink(entity)
      result.push(entity)
    end
  end
  
  result
end

##############################################################################
# Main program
##############################################################################
begin
  if __FILE__ == $0
    cgi = CGI.new
    uri_path = cgi.path_info
    format = "html"
    page = 0

    # Adjust uri path to / if it's nil
    if uri_path == nil
      uri_path = "/"
    end
  
    # Check the format
    if match = /\.(.+)$/.match(uri_path)
      uri_path = uri_path.sub("." + match[1], "")
      format = match[1]
    elsif cgi['format'] != ""
      format = cgi['format']
    end

    # Check the page
    if cgi['page'] != ""
      page = cgi['page'].to_i
    end

    # Setup the blog base uri if not specified
    if $blog_base_uri == nil
      $blog_base_uri = "http://" << cgi.host
      if cgi.server_port != 80
        $blog_base_uri << ":#{cgi_server_port}"
      end
      $blog_base_uri << cgi.script_name
    end
    
    # Load plugins
    plugins = []
    if $plugins_directory != nil
      Find.find($plugins_directory) do |path|
        if File.extname(path) == ".rb"
          require "#{path}"
          plugins.push(File.basename(path, File.extname(path)))
        end
      end
    end
    
    # Load all entities
    entities = []
    Find.find($blog_data_directory) do |local_path|
      entity = parse_entity(local_path)
      entities.push(entity) if entity != nil
    end
  
    # Filter out pages
    pages = get_pages(entities)
    
    # Parse uri path
    uri_path, date_filter, tags_filter = parse_uri_path(uri_path)
  
    # Render!
    header_footer_variables = { :blog_title => $blog_title, :blog_base_uri => $blog_base_uri, :categories_info => get_categories_info(entities), :pages => pages}
    puts render(uri_path, entities, format, page, header_footer_variables, date_filter, tags_filter, plugins)
  end
rescue Exception => e
  puts "Content-type: text/plain\n\n"

  puts "#{$blog_title}\n\n"
  puts "An error occurred while processing your request"
  puts e.inspect
  puts e.backtrace
end
