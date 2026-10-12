-- npc_vendor.OverrideGoldCost for tools/pandaria/vendor-price.patch (same column as later TrinityCore cores).
-- -1 = the item's own price (every existing row keeps its price); 0 or more = copper per purchase at this vendor.
-- Run once. A second run stops with "Duplicate column name 'OverrideGoldCost'", which is harmless.
ALTER TABLE `npc_vendor` ADD COLUMN `OverrideGoldCost` BIGINT NOT NULL DEFAULT -1 AFTER `ExtendedCost`;
