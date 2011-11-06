# Add html paragraph tags to text if they are not already there.
def add_paragraphs(format, content, metadata = {})
  result = ""
  if (format == "html" || format == "atom") && content !~ /<p>/
    content.each do |line|
      result << "<p>" << line.strip << "</p>\n"
    end
  else
    result = content
  end
  
  result
end