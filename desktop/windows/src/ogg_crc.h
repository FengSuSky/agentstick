#pragma once

#include "byte_utils.h"

namespace agentstick {

class OggCRC {
public:
    static std::uint32_t Checksum(std::span<const std::uint8_t> data);
};

} // namespace agentstick
