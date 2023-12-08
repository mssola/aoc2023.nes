utils = require "utils"

utils.StartRun("1")

utils.MemTest("@test", {{0x08, "D6"}, {0x09, "A9"}})

-- The test appears to be done in a few frames. Let's run this several times
-- just in case.
for i = 0, 20, 1 do
  emu.frameadvance();
end

utils.EndRun()
