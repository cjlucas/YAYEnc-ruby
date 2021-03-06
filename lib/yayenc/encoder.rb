require 'stringio'
require 'zlib'

module YAYEnc

  class InvalidInputException < Exception; end;

  class Encoder
    SPECIAL_BYTES = [0x00, 0x0A, 0x0D, 0x3D, 0x2E]
    DEFAULT_LINE_WIDTH = 128

    def self.encode(src, options = {}, &block)
      new(src, options).encode(&block)
    end

    def initialize(src, options = {})
      @opts = {}

      if src.is_a?(String)
        @src_io = File.open(src, 'rb')
        @opts[:file_name] = File.basename(src)
      elsif src.is_a?(IO)
        @src_io = src
        @opts[:file_name] = options.fetch(:name)
      else
        raise InvalidInputException 'src must be an IO object or a path to a file'
      end

      @src_io.rewind

      @opts[:part_size] = options.fetch(:part_size, @src_io.size)
      @opts[:line_width] = options.fetch(:line_width, DEFAULT_LINE_WIDTH)
    end

    def encode(&block)
      parts = []
      total_parts = (@src_io.size / @opts[:part_size].to_f).ceil
      cur_part_num = 1
      start_byte = 1
      crc32 = 0

      until @src_io.eof?
        part = encode_part(@src_io.read(@opts[:part_size]))
        part.name = @opts[:file_name]
        part.total_size = @src_io.size
        part.part_num = cur_part_num
        part.part_total = total_parts
        part.start_byte = start_byte
        part.end_byte = start_byte + part.part_size - 1

        crc32 = Zlib.crc32_combine(crc32, part.pcrc32, part.part_size)
        part.crc32 = crc32 if part.final_part?

        block_given? ? block.call(part) : parts << part

        cur_part_num += 1
        start_byte = part.end_byte + 1
      end
      @src_io.close

      parts unless block_given?
    end

    private

    def encode_part(data)
      part = Part.new
      part.line_width = @opts[:line_width]
      part.part_size = data.size

      line_byte_cnt = 0
      data.each_byte do |byte|
        enc = (byte + 42) % 256
        part.pcrc32 = Zlib.crc32(byte.chr, part.pcrc32)

        if SPECIAL_BYTES.include?(enc)
          part << 0x3D # =
          line_byte_cnt += 1
          enc = (enc + 64) % 256
        end

        part << enc
        line_byte_cnt += 1

        if line_byte_cnt >= @opts[:line_width]
          part << [0x0D, 0x0A]
          line_byte_cnt = 0
        end
      end

      part
    end
  end
end
