# stdlib
require "fiddle/import"

# modules
require "blingfire/model"
require "blingfire/version"

module BlingFire
  class Error < StandardError; end

  class << self
    attr_accessor :ffi_lib
  end
  lib_name =
    if Gem.win_platform?
      "blingfiretokdll.dll"
    elsif RbConfig::CONFIG["host_os"] =~ /darwin/i
      "libblingfiretokdll.dylib"
    else
      "libblingfiretokdll.so"
    end
  vendor_lib = File.expand_path("../vendor/#{lib_name}", __dir__)
  self.ffi_lib = [vendor_lib]

  # friendlier error message
  autoload :FFI, "blingfire/ffi"

  class << self
    def lib_version
      FFI.GetBlingFireTokVersion
    end

    def load_model(path)
      Model.new(path)
    end

    def text_to_words(text)
      text_to(text, " ") do |t, out|
        FFI.TextToWords(t, t.bytesize, out, out.size)
      end
    end

    def text_to_words_with_model(model, text)
      text_to(text, " ") do |t, out|
        FFI.TextToWordsWithModel(t, t.bytesize, out, out.size, model)
      end
    end

    def text_to_words_with_offsets(text)
      text_to_with_offsets(text, " ") do |t, out, start_offsets, end_offsets|
        FFI.TextToWordsWithOffsets(t, t.bytesize, out, start_offsets, end_offsets, out.size)
      end
    end

    def text_to_words_with_offsets_with_model(model, text)
      text_to_with_offsets(text, " ") do |t, out, start_offsets, end_offsets|
        FFI.TextToWordsWithOffsetsWithModel(t, t.bytesize, out, start_offsets, end_offsets, out.size, model)
      end
    end

    def text_to_sentences(text)
      text_to(text, "\n") do |t, out|
        FFI.TextToSentences(t, t.bytesize, out, out.size)
      end
    end

    def text_to_sentences_with_model(model, text)
      text_to(text, "\n") do |t, out|
        FFI.TextToSentencesWithModel(t, t.bytesize, out, out.size, model)
      end
    end

    def text_to_sentences_with_offsets(text)
      text_to_with_offsets(text, "\n") do |t, out, start_offsets, end_offsets|
        FFI.TextToSentencesWithOffsets(t, t.bytesize, out, start_offsets, end_offsets, out.size)
      end
    end

    def text_to_sentences_with_offsets_with_model(model, text)
      text_to_with_offsets(text, "\n") do |t, out, start_offsets, end_offsets|
        FFI.TextToSentencesWithOffsetsWithModel(t, t.bytesize, out, start_offsets, end_offsets, out.size, model)
      end
    end

    def text_to_ids(model, text, max_len = nil, unk_id = 0)
      text = encode_utf8(text.dup) unless text.encoding == Encoding::UTF_8
      ids = Fiddle::Pointer.malloc((max_len || text.size) * Fiddle::SIZEOF_INT)
      out_size = FFI.TextToIds(model, text, text.bytesize, ids, ids.size, unk_id)
      check_status out_size, ids
      ids[0, (max_len || out_size) * Fiddle::SIZEOF_INT].unpack("i!*")
    end

    def free_model(model)
      FFI.FreeModel(model)
    end

    def normalize_spaces(text)
      u_space = 0x20
      text = encode_utf8(text.dup) unless text.encoding == Encoding::UTF_8
      out = Fiddle::Pointer.malloc([text.bytesize * 1.5, 20].max)
      out_size = FFI.NormalizeSpaces(text, text.bytesize, out, out.size, u_space)
      check_status out_size, out
      encode_utf8(out.to_str(out_size))
    end

    private

    def check_status(ret, ptr)
      raise Error, "Not enough memory allocated" if ret == -1 || ret > ptr.size
    end

    def text_to(text, sep)
      text = encode_utf8(text.dup) unless text.encoding == Encoding::UTF_8
      # TODO allocate less, and try again if needed
      out = Fiddle::Pointer.malloc([text.bytesize * 1.5, 20].max)
      out_size = yield(text, out)
      check_status out_size, out
      encode_utf8(out.to_str(out_size - 1)).split(sep)
    end

    def text_to_with_offsets(text, sep)
      text = encode_utf8(text.dup) unless text.encoding == Encoding::UTF_8
      # TODO allocate less, and try again if needed
      out = Fiddle::Pointer.malloc([text.bytesize * 1.5, 20].max)

      start_offsets = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT * out.size)
      end_offsets = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT * out.size)

      out_size = yield(text, out, start_offsets, end_offsets)

      check_status out_size, out

      result = encode_utf8(out.to_str(out_size - 1)).split(sep)
      byte_offsets = start_offsets.to_s(Fiddle::SIZEOF_INT * result.size).unpack("i*")
      offsets = []

      pos = 0
      text.each_char.with_index do |c, i|
        offsets << i if pos == byte_offsets[offsets.size]
        pos += c.bytesize
      end

      result.zip(offsets)
    end

    def encode_utf8(text)
      text.force_encoding(Encoding::UTF_8)
    end
  end
end
