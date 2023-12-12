utils = require "utils"

utils.StartRun("3")

utils.MemTest("@test", {{0x0C, "BE"}, {0x0D, "35"}, {0x0E, "08"}, {0x0F, "00"}})

-- This test is either flaky or it takes a long ass time. Let's wait for a
-- little while longer than usual.
for i = 0, 300, 1 do
  emu.frameadvance();
end

utils.EndRun()
