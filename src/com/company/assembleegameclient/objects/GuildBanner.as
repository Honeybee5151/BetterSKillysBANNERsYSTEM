package com.company.assembleegameclient.objects {
import com.company.assembleegameclient.map.Camera;
import flash.display.BitmapData;
import kabam.rotmg.CustomGuildBanners.BannerActivate;

public class GuildBanner extends GameObject {
    public var customBannerTexture_:BitmapData = null;
    public var hasCustomBanner_:Boolean = false;
    public var guildId_:int = 0;

    public function GuildBanner(objectXML:XML) {
        super(objectXML);

        // AUTO-APPLY banner when entity is constructed
        // This ensures banners are reapplied even when recreated from render distance
        BannerActivate.applyBannerOnEntityCreation(this);
    }

    override protected function getTexture(camera:Camera, angle:int):BitmapData {
        // Use custom banner texture if set, else default texture
        if (this.hasCustomBanner_ && this.customBannerTexture_ != null) {
            return this.customBannerTexture_;
        }
        return super.getTexture(camera, angle);
    }
}
}