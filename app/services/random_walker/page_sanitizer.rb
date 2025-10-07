# frozen_string_literal: true

require "nokogiri"

module RandomWalker
  module PageSanitizer
    module_function

    def sanitize(html, base_uri)
      serialized = html.to_s
      raise StandardError, "Empty response" if serialized.strip.empty?

      document = Nokogiri::HTML(serialized)

      document.css("script, iframe, frame, frameset, object, embed").remove
      document.css("meta[http-equiv]").each do |node|
        node.remove if node["http-equiv"].to_s.casecmp("refresh").zero?
      end

      document.css("*[href], *[src]").each do |node|
        %w[href src].each do |attribute|
          value = node[attribute]
          next unless value

          stripped = value.strip.downcase
          node.remove_attribute(attribute) if stripped.start_with?("javascript:")
        end
      end

      document.traverse do |node|
        next unless node.element?

        node.attribute_nodes.each do |attribute|
          node.remove_attribute(attribute.name) if attribute.name.downcase.start_with?("on")
        end
      end

      if base_uri
        head = document.at("head")
        unless head
          head = Nokogiri::XML::Node.new("head", document)
          document.root&.children&.first ? document.root.children.first.add_previous_sibling(head) : document.root&.add_child(head)
        end

        if head
          base_tag = head.at("base")
          unless base_tag
            base_tag = Nokogiri::XML::Node.new("base", document)
            head.prepend_child(base_tag)
          end
          base_tag["href"] = base_uri.to_s
        end
      end

      document.to_html
    end
  end
end
