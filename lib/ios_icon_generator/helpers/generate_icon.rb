# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'ios_icon_generator/helpers/images_sets_definition'

module IOSIconGenerator
  module Helpers
    def self.generate_icon(icon_path:, output_folder:, types:, parallel_processes: nil, progress: nil)
      matches = /(\d+)x(\d+)/.match(`magick identify "#{icon_path}"`)
      raise 'There is no icon at the path specified.' unless File.exist?(icon_path)

      raise 'The icon specified must be .pdf.' if File.extname(icon_path) != '.pdf'

      raise 'Unable to verify icon. Please make sure it\'s a valid pdf file and try again.' if matches.nil?

      width, height = matches.captures
      raise 'Invalid pdf specified.' if width.nil? || height.nil?

      raise "The icon must at least be 1024x1024, it currently is #{width}x#{height}." unless width.to_i >= 1024 && height.to_i >= 1024

      appiconset_path = File.join(output_folder, "#{types.include?(:imessage) ? 'iMessage App Icon' : 'AppIcon'}.#{types.include?(:imessage) ? 'stickersiconset' : 'appiconset'}")

      FileUtils.mkdir_p(appiconset_path)

      generate_icon = lambda { |base_path, width, height|
        size = [width, height].max
        system(
          'magick',
          'convert',
          '-density',
          '400',
          base_path,
          '-colorspace',
          'sRGB',
          '-type',
          'truecolor',
          '-resize', "#{size}x#{size}",
          '-gravity',
          'center',
          '-crop',
          "#{width}x#{height}+0+0",
          '+repage',
          File.join(appiconset_path, "Icon-#{width}x#{height}.png")
        )
      }

      types.each do |type1|
        types.each do |type2|
          raise "Incompatible types used together: #{type1} and #{type2}. These types cannot be added to the same sets; please call the command twice with each different type." if Helpers.type_incompatible?(type1, type2)
        end
      end

      images_sets = Helpers.images_sets(types)

      smaller_sizes = []
      images_sets.each do |image|
        width, height = /(\d+(?:\.\d)?)x(\d+(?:\.\d)?)/.match(image['size'])&.captures
        scale, = /(\d+(?:\.\d)?)x/.match(image['scale'])&.captures
        raise "Invalid size parameter in Contents.json: #{image['size']}" if width.nil? || height.nil? || scale.nil?

        scale = scale.to_f
        width = width.to_f * scale
        height = height.to_f * scale

        filename = "Icon-#{width}x#{height}.png"
        image['filename'] = filename
        if width > 512 || height > 512
          generate_icon.call(icon_path, width, height)
        else
          smaller_sizes << [width, height]
        end
      end

      total = smaller_sizes.count + 2
      progress&.call(nil, total)

      max_size = smaller_sizes.flatten.max
      temp_icon_path = File.join(output_folder, '.temp_icon.pdf')
      begin
        system('magick', 'convert', '-density', '400', icon_path, '-colorspace', 'sRGB', '-type', 'truecolor', '-scale', "#{max_size}x#{max_size}", temp_icon_path)
        progress&.call(1, total)
        Parallel.each(
          smaller_sizes,
          in_processes: parallel_processes,
          finish: lambda do |_item, i, _result|
            progress&.call(i + 1, total)
          end
        ) do |width, height|
          generate_icon.call(temp_icon_path, width, height)
        end
      ensure
        FileUtils.rm(temp_icon_path) if File.exist?(temp_icon_path)
      end

      contents_json = {
        images: images_sets,
        info: {
          version: 1,
          author: 'xcode',
        },
      }

      File.write(File.join(appiconset_path, 'Contents.json'), JSON.generate(contents_json))

      progress&.call(total - 1, total)
    end
  end
end
