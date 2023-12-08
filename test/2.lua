utils = require "utils"

utils.StartRun("2")

utils.MemTest("@test", {{0x0B, "00"}, {0x0C, "01"}, {0x0D, "0F"}, {0x0E, "FD"}})

-- The test appears to be done in a few frames. Let's run this several times
-- just in case.
for i = 0, 20, 1 do
  emu.frameadvance();
end

utils.EndRun()
