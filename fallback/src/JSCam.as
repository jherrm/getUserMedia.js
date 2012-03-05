package {

import flash.display.Sprite;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageQuality;
import flash.display.StageScaleMode;
import flash.external.ExternalInterface;
import flash.events.StatusEvent;
import flash.media.Camera;
import flash.media.Video;
import flash.system.Capabilities;
import flash.system.Security;
import flash.system.SecurityPanel;
import flash.utils.*;

public class JSCam extends Sprite {

	private static var camera:Camera = null;
	private static var video:Video = null;
	private static var buffer:BitmapData = null;
	// private static var jpgQuality:Number = 85;
	private static var flashvars:Object = null;
	private static var interval:uint = 0;
	private static var stream:uint = 0;
	private static var mode:String = "callback";
	private static var _stage:Stage;

	public function JSCam() {

		_stage = stage;

		// Emulate display behavior of getUserMedia
		stage.align     = StageAlign.TOP_LEFT;
		// Stretch to fit <object> element
		// http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/display/StageScaleMode.html
		stage.scaleMode = StageScaleMode.EXACT_FIT;

		Security.allowDomain("*");

		flashvars = this.root.loaderInfo.parameters;

		if (flashvars.mode) {
			mode = flashvars.mode;
		} else {
			ExternalInterface.call('webcam.debug', "error", "No camera mode present, falling back...");
		}

		if (flashvars.quality) {
			stage.quality = flashvars.quality ? flashvars.quality : StageQuality.HIGH;
		}

		camera = getCamera();

		if (null != camera) {

			 // muted == true if user denied access to the camera
 			if(camera.muted) {
				// Instead of showing the default allow/block access panel,
				// show the privacy panel which has a "Remember" checkbox.
				Security.showSettings(SecurityPanel.PRIVACY);
			}

			// http://www.adobe.com/support/flash/action_scripts/actionscript_dictionary/actionscript_dictionary133.html
			camera.addEventListener(StatusEvent.STATUS, camera_statusHandler);

			camera.setQuality(0, 100);
			camera.setMode(stage.stageWidth, stage.stageHeight, 24, false);

			ExternalInterface.addCallback("capture", capture);
			ExternalInterface.addCallback("save", save);
			ExternalInterface.addCallback("setCamera", setCamera);
			ExternalInterface.addCallback("getCameraList", getCameraList);

			video = new Video(stage.stageWidth, stage.stageHeight);
			video.attachCamera(camera);
			// video.width = camera.width;
			// video.height = camera.height;
			addChild(video);

		} else {
			ExternalInterface.call('webcam.debug', "error", "No camera was detected.");
		}
	}

	/**
	 * Flash's Camera.getCamera returns many "cameras" that aren't what we actually want.
	 * This function tries to get the best camera and falls back to Camera.getCamera().
	 *
	 * From: http://www.squidder.com/2009/03/09/trick-auto-select-mac-isight-in-flash/
	 */
	protected function getCamera():Camera
	{
		var id:Number = -1;
		for(var i:int = 0, l:int = Camera.names.length; i < l; i++) {
			if (Camera.names[i] == "USB Video Class Video") {
				id = i;
				break;
			}
		}
		if (id > -1) {
			// API docs: Camera.getCamera("name")
			// "name" is actually an ID number converted to a string
			return Camera.getCamera(id.toString());
		}

		return Camera.getCamera();
	}

	/**
	 * Called when a user denies or allows access to a camera.
	 */
	protected function camera_statusHandler(event:StatusEvent):void
	{
		//trace("camera_statusHandler", "code:", event.code);
		if(event.code == "Camera.Muted")
		{
			// _activityTimer.stop();
			// dispatchEvent(new Event("noCameraAccess"));
			ExternalInterface.call('webcam.debug', "notify", "Camera stopped");
		}
		else if(event.code == "Camera.Unmuted")
		{
			// Camera has been unmuted, now wait for some activity
			// _camera.addEventListener(ActivityEvent.ACTIVITY, camera_activityHandler);
			ExternalInterface.call('webcam.debug', "notify", "Camera started");
		}

	}

	public static function getCameraList():Array {

		var list:Array = new Array();

		for (var i:int = 0, l:int = Camera.names.length; i < l; i++) {
			list[i] = Camera.names[i];
		}
		return list;
	}

	public static function setCamera(id:Number):Boolean {

		if (0 <= id && id < Camera.names.length) {
			camera = Camera.getCamera(id.toString());
			camera.setQuality(0, 100);
			camera.setMode(_stage.stageWidth, _stage.stageHeight, 24, false);
			return true;
		}
		return false;
	}

	public static function save():Boolean {

		if ("stream" == mode) {

			return true;

		} else if (null != buffer) {

			if ("callback" == mode) {

				for (var i:int = 0; i < camera.height; ++i) {

					var row:String = "";
					for (var j:int = 0; j < camera.width; ++j) {
						row += buffer.getPixel(j, i);
						row += ";";
					}
					ExternalInterface.call("webcam.onSave", row);
				}
			} else {
				ExternalInterface.call('webcam.debug', "error", "Unsupported storage mode.");
			}

			buffer = null;
			return true;
		}
		return false;
	}

	public static function capture(time:Number):Boolean {

		if (null != camera) {

			if (null != buffer) {
				trace('buffer is not null');
				return false;
			}

			buffer = new BitmapData(_stage.stageWidth, _stage.stageHeight);
			// buffer = new BitmapData(320, 240);

			ExternalInterface.call('webcam.debug', "notify", "Capturing started.");

			if ("stream" == mode) {
				_stream();
				return true;
			}

			if (!time) {
				time = -1;
			} else if (time > 10) {
				time = 10;
			}

			_capture(time + 1);

			return true;
		}
		return false;
	}

	private static function _capture(time:Number):void {

		if (0 != interval) {
			clearInterval(interval);
		}

		if (0 == time) {
			buffer.draw(video);
			ExternalInterface.call('webcam.onCapture');
			ExternalInterface.call('webcam.debug', "notify", "Capturing finished.");
		} else {
			ExternalInterface.call('webcam.onTick', time - 1);
			interval = setInterval(_capture, 1000, time - 1);
		}
	}


	private static function _stream():void {

		buffer.draw(video);

		if (0 != stream) {
			clearInterval(stream);
		}

		for (var i:int = 0; i < camera.height; ++i) {

			var row:String = "";
			for (var j:int = 0; j < camera.width; ++j) {
				row+= buffer.getPixel(j, i);
				row+= ";";
			}
			ExternalInterface.call("webcam.onSave", row);
		}

		stream = setInterval(_stream, 10);
	}

} // end class
} // end package
