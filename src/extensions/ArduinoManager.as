package extensions
{
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.MouseEvent;
	import flash.events.NativeProcessExitEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.system.Capabilities;
	import flash.utils.ByteArray;
	import flash.utils.getQualifiedClassName;
	
	import blocks.Block;
	import blocks.BlockIO;
	
	import cc.customcode.uibot.uiwidgets.lightSetter.LightSensor2;
	import cc.customcode.uibot.util.AppTitleMgr;
	import cc.customcode.uibot.util.PopupUtil;
	import cc.customcode.uibot.util.StringUtil;
	import cc.customcode.util.StringChecker;
	
	import org.aswing.JOptionPane;
	
	import translation.Translator;
	
	import util.ApplicationManager;
	import util.JSON;
	import util.LogManager;

//	import util.SharedObjectManager;

	public class ArduinoManager extends EventDispatcher
	{
	
		//public var arduinoCliPath:String = "e:\\dev\\arduinocli";
		
		private static var _instance:ArduinoManager;
		public var _scratch:eBlock;
		public var jsonObj:Object;
		
		public var hexCode:String;
		public var token:String;
		public var output:String;
		public var ccode:String = "";
		public var hexPath:String;
		public var isUploading:Boolean = false;
		
		private var process:NativeProcess;
		public var hasUnknownCode:Boolean = false;
		private var ccode_setup:String = "";
		private var ccode_setup_fun:String = "";
//		private var ccode_setup_def:String = "";
		private var ccode_loop:String = ""
		private var ccode_loop2:String = ""
		private var ccode_def:String = ""
		private var ccode_inc:String = ""
		private var ccode_pointer:String="setup"
		private var ccode_func:String = "";
		//添加 && ||
		private var mathOp:Array=["+","-","*","/","%",">","=","<","&","&&","|","||","!","not","rounded"];
		
		private var arrayList:Array = []; //*JC*
		private var arrayStringList:Array = [];
		
		private var varList:Array = [];
		private var varStringList:Array = [];
		
		private var varListWrite:Array=[]
		private var paramList:Array=[]
		private var moduleList:Array=[];
		private var funcList:Array = [];
		
		public var unknownBlocks:Array = [];
		
		// maintance of project and arduino path
		private var arduinoPath:String;
//		private var avrPath:String = "";
		private var arduinoLibPath:String = "";
		private var projectPath:String = "";

		private var EVENT_NATIVE_DONE:String = "EVENT_NATIVE_DONE"
		private var EVENT_LIBCOMPILE_DONE:String = "EVENT_LIBCOMPILE_DONE"
		private var EVENT_COMPILE_DONE:String = "EVENT_COMPILE_DONE"
		
		public var mainX:int = 0;
		public var mainY:int = 0;
		

		
		private var codeTemplate:String = ( <![CDATA[#include <Arduino.h>
//include

//define
//serialParser

void setup(){
//setup
}

void loop(){
//serialParserCall
//loop
_loop();
}
void _loop(){
//_loop
}

void _delay(float seconds){
long endTime = millis() + seconds * 1000;
while(millis() < endTime)_loop();
}

//function


]]> ).toString();//delay(50);
		
		private var codeSerialParser:String = ( <![CDATA[
char inputBuf[64];
int inputIndex;
void parseSerialInput(){
if(Serial.available()){
char c = Serial.read();
inputBuf[inputIndex++] = c;
if(c=='\\n'){
int value;
//parseList
memset(inputBuf,0,64);
inputIndex = 0;
}
}
}
]]> ).toString();
		
		private var codeSerialScanf:String = ( <![CDATA[
if(sscanf(inputBuf,"param=%d",&value)){
param = value;
//Serial.printf("param=%d\\n",value);
}
]]> ).toString();
		
		private var serialParserInoFile:String = ( <![CDATA[
char buf[64];
char readLine[64];
bool lineParsed = true;
int bufIndex = 0;

void updateVar(char * varName,double * var)
{
  char tmp[16];
  int value,i;
  while(Serial.available()){
	char c = Serial.read();
	buf[bufIndex++] = c;
	if(c=='\n'){
	  memset(readLine,0,64);
	  memcpy(readLine,buf,bufIndex);
	  memset(buf,0,64);
	  bufIndex = 0;
	  lineParsed = false;
	}
  }
  if(!lineParsed){
	char * tmp;
	char * str;
	str = strtok_r(readLine, "=", &tmp);
	if(str!=NULL && strcmp(str,varName)==0){
	  float v = atof(tmp);
	  *var = v;
	  lineParsed = true;
	}
  }
}
]]> ).toString();
		
		public static function sharedManager():ArduinoManager{
			if(_instance==null){
				_instance = new ArduinoManager;
			}
			return _instance;
		} 
		
		public function ArduinoManager()
		{

		}
		
		public function clearTempFiles():void
		{

			if(File.applicationStorageDirectory.exists){
				File.applicationStorageDirectory.deleteDirectory(true);
			}
			PopupUtil.showConfirm(Translator.map("Restart App?"),eBlock.app.restart);
		}
		
		public function setScratch(scratch:eBlock):void{
			_scratch = scratch;
		}

		private function parseMath(blk:Object):CodeObj{
			var op:Object= blk[0]
			var mp1:CodeBlock=getCodeBlock(blk[1]);
			var mp2:CodeBlock=getCodeBlock(blk[2]);
			if(op=="="){
				op="==";
			}
			if(mp1.type=="string"){
				if(!isNaN(Number(mp1.code))){
					mp1.type = "number";
					mp1.code = Number(mp1.code);
				}
			}
			if(mp2.type=="string"){
				if(!isNaN(Number(mp2.code))){
					mp2.type = "number";
					mp2.code = Number(mp2.code);
				}
			}
			//			var isStringValue:Boolean = false;
			//			if(getQualifiedClassName(mp1) == "Array")
			//				mp1 = getCodeBlock(blk[1])
			//			if(getQualifiedClassName(mp2) == "Array")
			//				mp2 = getCodeBlock(blk[2]);
			//			else
			//			{
			//				if(mp1 is String){
			//					isStringValue = mp1.indexOf("readDataLine")>-1;
			//				}
			//			}
			var code:String = StringUtil.substitute("({0}) {1} ({2})",mp1.type=="obj"?mp1.code.code:mp1.code ,op,mp2.type=="obj"?mp2.code.code:mp2.code);
			if(op=="=="){
				if(mp1.type=="string"&&mp2.type=="string"){
					code = StringUtil.substitute("({0}.equals(\"{1}\"))",mp1.code,mp2.code);
				}else{
					code = StringUtil.substitute("(({0})==({1}))",mp1.type=="obj"?mp1.code.code:mp1.code,mp2.type=="obj"?mp2.code.code:mp2.code);
				}
			}else if(op=="%"){
				code = StringUtil.substitute("fmod({0},{1})",mp1.type=="obj"?mp1.code.code:mp1.code,mp2.type=="obj"?mp2.code.code:mp2.code);
			}else if(op=="not"){
				code = StringUtil.substitute("!({0})",mp1.type=="obj"?mp1.code.code:mp1.code);
			}else if(op=="rounded"){
				code = StringUtil.substitute("round({0})",mp1.type=="obj"?mp1.code.code:mp1.code);
			}
			return new CodeObj(code);
		}
		
		
		private function parseVarRead(blk:Object):CodeObj{
			var varName:Object = blk[1]
			if(varList.indexOf(varName)==-1){
				varList.push(varName);
			}
			var code:CodeObj = new CodeObj(StringUtil.substitute("{0}",castVarName(varName.toString())));
			return code;
		}
		
		
		private function getArrayValue( varValue:*, arrayName:String ):*{
					
			var incCodeBlock:Object = {code:{setup:"",work:"",def:"",inc:"#include \"ListLib.h\"\n",loop:""}}
			if(moduleList.indexOf(incCodeBlock)==-1)	moduleList.push(incCodeBlock);
			
			if(arrayList.indexOf(arrayName)==-1)
				arrayList.push(arrayName)
			
			//varValue = varValue is CodeObj?varValue.code:varValue;
			
			
			var varType:* = getQualifiedClassName(varValue);
			
			if( varType == "Array"){
				varValue = getCodeBlock(varValue);
				//varvalue = varValue.type=="obj"?varValue.code:varValue;
				return varValue.code;
			}else{
				return varValue;
			}
			
			
			//varValue = varValue is CodeBlock?varValue.code: varValue;
			
			
					
	
			
			
			//--------
		}
		
		private function parseArraySet(blk:Object):String{
			var arrayName:String = blk[2];
			var varValue:* =  blk[1] ;
						
			varValue = getArrayValue(varValue, arrayName );
			var varValueIsObj:Boolean = varValue is CodeObj;
			varValue = varValue is CodeObj ? varValue.code : varValue;
			
			
			return (StringUtil.substitute("{0}.Add({1});\n",castVarName(arrayName), varValue ));
			
		}
		
		private function parseArrayInsertAt(blk:Object):String{
			var arrayName:String = blk[3];
			var varValue:* =  blk[1] ;
			
			var index:* =  blk[2] ;
			index = getArrayValue(index, arrayName );
			
			varValue = getArrayValue(varValue, arrayName );
			var varValueIsObj:Boolean = varValue is CodeObj;
			varValue = varValue is CodeObj ? varValue.code : varValue;
			
			index = getArrayValue(index, arrayName );
			if(index=="last"){
				index = StringUtil.substitute("{0}.Count()-1",castVarName(arrayName) );
			}else if(index=="random"){
				index = StringUtil.substitute(" random(0, {0}.Count()-1) ",castVarName(arrayName) );
			}else if( StringChecker.IsNumber(index) ){
			  index =  Number(index)-1 ;
			}else if (index is CodeObj) {
				index =index.code;
			}
						
			if(StringChecker.IsNumber(varValue) || varValueIsObj){
				return (StringUtil.substitute("{0}.Insert({2}, {1});\n",castVarName(arrayName), varValue, index ));
			}else{ //- is string
				if( arrayStringList.indexOf(arrayName)==-1 )	arrayStringList.push(arrayName);
				return (StringUtil.substitute("{0}.Insert({2}, \"{1}\");\n",castVarName(arrayName),varValue, index ));
			}
			
		}
		
		private function parseArrayReplace(blk:Object):String{
			var arrayName:String = blk[2];
			var varValue:* =  blk[3] ;
			var index:* =  blk[1] ;
			
			varValue = getArrayValue(varValue, arrayName );
			var varValueIsObj:Boolean = varValue is CodeObj;
			varValue = varValue is CodeObj ? varValue.code : varValue;
			
			index = getArrayValue(index, arrayName );
			
			
			if(index=="last"){
				index = StringUtil.substitute("{0}.Count()-1",castVarName(arrayName) );
			}else if(index=="random"){
				index = StringUtil.substitute(" random(0, {0}.Count()-1) ",castVarName(arrayName) );
			}else if( StringChecker.IsNumber(index) ){
				index =  Number(index)-1 ;
			}else{
				index =index.code;
			}
			
			var varIsNum:Boolean = StringChecker.IsNumber(varValue);
			if(varIsNum || varValueIsObj){
				return (StringUtil.substitute("{0}.Replace({2}, {1});\n",castVarName(arrayName), varValue, index ));
			}else{ //- is string
				if( arrayStringList.indexOf(arrayName)==-1 )	arrayStringList.push(arrayName);
				return (StringUtil.substitute("{0}.Replace({2}, \"{1}\");\n",castVarName(arrayName),varValue, index ));
			}
			
		}
		
		private function parseArrayDelete(blk:Object):String{
			var arrayName:String = blk[2];
			var index:* =  blk[1] ;
			var indexIsObj:Boolean = false;
			
			index = getArrayValue(index, arrayName );
			
			if(index=="last"){
				return (StringUtil.substitute("{0}.Remove( {0}.Count()-1 );\n",castVarName(arrayName) ));
			}else if(index=="all"){
				return (StringUtil.substitute("{0}.RemoveRange(0, {0}.Count()-1 );\n",castVarName(arrayName) ));
			} else if(  StringChecker.IsNumber(index) ){
				index = Number(index)-1;
			}else if ( index is CodeObj) {
				index =index.code;
				indexIsObj = true;
			}
			
			return (StringUtil.substitute("{0}.Remove({1});\n",castVarName(arrayName), index ));
						
		}
		
		private function parseArrayGet(blk:Object):CodeObj{
			var arrayName:String = blk[2];
			var index:* =  blk[1] ;
			var indexIsObj:Boolean = false;
			
			index = getArrayValue(index, arrayName );
			
			if(index=="last"){
				index = StringUtil.substitute("{0}.Count()-1",castVarName(arrayName) );
			}else if(index=="random"){
				index = StringUtil.substitute(" random(0, {0}.Count()-1) ",castVarName(arrayName) );
			}else if(  StringChecker.IsNumber(index) ){
				index = Number(index)-1;
			}else{
				index =index.code;
				indexIsObj = true;
			}
			
			//return StringUtil.substitute("{0}[{1}]",castVarName(arrayName), index ) ;
			
			return  new CodeObj(   StringUtil.substitute("{0}[{1}]",castVarName(arrayName), index )    );
					
			
			
		}
		
		private function parseArrayLength(blk:Object):CodeObj{
			var arrayName:String = blk[1];
						
			return  new CodeObj(StringUtil.substitute("{0}.Count()",castVarName(arrayName) ));
			
		}
		
		private function parseArrayContains(blk:Object):CodeObj{
			var arrayName:String = blk[1];
			var varValue:* =  blk[2] ;
			
			varValue = getArrayValue(varValue, arrayName );
			var varValueIsObj:Boolean = varValue is CodeObj;
			varValue = varValue is CodeObj ? varValue.code : varValue;
			
			var varIsNum:Boolean = StringChecker.IsNumber(varValue); //- puede ser numérico tipo "2"
			if(varIsNum || varValueIsObj){
				return new CodeObj(StringUtil.substitute("{0}.Contains({1})",castVarName(arrayName), varValue ));
			}else{ //- is string
				if( arrayStringList.indexOf(arrayName)==-1 )	arrayStringList.push(arrayName);
				return new CodeObj(StringUtil.substitute("{0}.Contains(\"{1}\")",castVarName(arrayName),varValue));
			}
		}
		
		
		private function parseVarSet(blk:Object):String{
			var varName:String = blk[1]
			if(varList.indexOf(varName)==-1)
				varList.push(varName)
			var varValue:* = blk[2] is CodeObj?blk[2].code:blk[2];
			var varType:* = getQualifiedClassName(varValue);
			if( varType == "Array"){
				varValue = getCodeBlock(varValue);
				if(varValue.type=="obj"){
					if(varValue.code.code.indexOf("ir.getString()")>-1){
						varStringList.push(varName);
					}
				}else if(varValue.type=="string"){
					if(varStringList.indexOf(varName)==-1){
						varStringList.push(varName);
					}
				}
				return (StringUtil.substitute("{0} = {1};\n",castVarName(varName),varValue.type=="obj"?varValue.code.code:varValue.code))
			}else if(varType=="String" && !StringChecker.IsNumber(varValue)){
				if(varStringList.indexOf(varName)==-1){
					varStringList.push(varName);
				}
			   return (StringUtil.substitute("{0} = \"{1}\";\n",castVarName(varName),varValue));;
			}else{
				return (StringUtil.substitute("{0} = {1};\n",castVarName(varName),varValue is CodeObj?varValue.code:varValue));
			}
		}
		
		private function parseVarShow(fun:Object):CodeObj{
			var param:Object = fun[1]
			if(paramList.indexOf(param)==-1)
				paramList.push(param)
			var funcode:CodeObj=new CodeObj(StringUtil.substitute("Serial.print(\"{0}=\");Serial.println(\"{1}\");\n",param,param));
			return funcode;
		}
		
		private function parseDelay(fun:Object):String{
			var cBlk:CodeBlock=getCodeBlock(fun[1]);
			var funcode:String=(StringUtil.substitute("_delay({0});\n",cBlk.type=="obj"?cBlk.code.code:cBlk.code));
			return funcode;
		}
		private function parseDoRepeat(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var repeatCode:String=StringUtil.substitute("for(int __i__=0;__i __<{0};++__i__)\n{\n",initCode.type=="obj"?initCode.code.code:initCode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:Object = blk[2][i]
					var cBlk:CodeBlock=getCodeBlock(b);
					repeatCode+=cBlk.type=="obj"?cBlk.code.code:cBlk.code;
				}
			}
			repeatCode+="}\n";
			return repeatCode;
		}
		/*private function parseForever(blk:Object):String{
			var forEverCode:String = "while(1){\n";
			if(blk[1])
			{
				if(blk[1] is Array)
				{
					for(var k:int=0;k<blk[1].length;k++)
					{
						var initCode:CodeBlock = getCodeBlock(blk[1][k]);
						forEverCode+=initCode.type=="obj"?initCode.code.code:initCode.code;
					}
				}
				else
				{
					initCode = getCodeBlock(blk[1]);
					forEverCode+=initCode.type=="obj"?initCode.code.code:initCode.code;
				}
			}
			
			
			forEverCode+="}\n";
			return forEverCode;
		}*/
		private function parseDoWaitUntil(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var untilCode:String=StringUtil.substitute("while(!({0}))\n{\n_loop();\n}\n",initCode.type=="obj"?initCode.code.code:initCode.code);
			return (untilCode);
		}
		private function parseDoUntil(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var untilCode:String=StringUtil.substitute("while(!({0}))\n{\n_loop();\n",initCode.type=="obj"?initCode.code.code:initCode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:Object = blk[2][i]
					var cBlk:CodeBlock=getCodeBlock(b);
					untilCode+=cBlk.type=="obj"?cBlk.code.code:cBlk.code;
				}
			}
			untilCode+="}\n";
			return (untilCode);
		}
		private function parseCall(blk:Object):String{
			
			var vars:String = "";
			var funcName:String = blk[1];
			if(funcName.indexOf("%")==0){
				funcName = "func "+funcName;
			}
			var ps:Array = funcName.split(" ");
			var tmp:Array = [castVarName(ps[0], true)];
			for(var i:uint=0;i<ps.length;i++){
				if(i>0){
					if(ps[i].indexOf("%")>-1){
						tmp.push(ps[i].substr(1,1));
					}
				}
			}
			ps = tmp;
			var params:Array = blk as Array;
			var cBlk:CodeBlock;
			for(i = 2;i<params.length;i++){
				cBlk = getCodeBlock(params[i]);
				//				trace("p:",params[i],cBlk.type,"end");
				if(i>2){
					vars +=",";
				}
				if(cBlk.type=="obj"){
					vars += cBlk.code.code;//(isNaN(Number(params[i]))?'"'+params[i]+'"':(params[i]==""?(ps[i-1]=="s"?'"s"':"false"):params[i]))+(i<params.length-1?", ":"");
				}else if(cBlk.type == "string"){
					vars += '"' + cBlk.code + '"';
				}else{
					vars += cBlk.code;
					
				}
			}
			var callCode:String = StringUtil.substitute("{0}({1});\n",ps[0],vars);
			return (callCode);
		}
		private function addFunction(blks:Array):void{
			var funcName:String = blks[0][1].split("&").join("_");
			for each(var o:Object in funcList){ 
				if(o.name==funcName){
					return;
				}
			}
			if(funcName.indexOf("%")==0){
				funcName = "func "+funcName;
			}
			var params:Array = funcName.split(" ");
			var tmp:Array = [params[0]];
			for(var i:uint=0;i<params.length;i++){
				if(i>0){
					if(params[i].indexOf("%")>-1){
						tmp.push(params[i].substr(1,1));
					}
				}
			}
			params = tmp;
			var vars:String = "";
			for(i = 1;i<params.length;i++){
				vars += (params[i]=='n'?("double"):(params[i]=='s'?"String":(params[i]=='b'?"boolean":(params[i]=='8'?"uint8_t":""))))+" "+castVarName(blks[0][2][i-1].split(" ").join("_"))+(i<params.length-1?", ":"");
			}
			var defFunc:String = "void "+castVarName(params[0], true)+"("+vars+");\n";
			if(ccode_def.indexOf(defFunc)==-1){
				ccode_def+=defFunc;
			}
			var funcCode:String = "void "+castVarName(params[0], true)+"("+vars+")\n{\n";
			for(i=0;i<blks.length;i++){
				if(i>0){
					
					var b:CodeBlock = getCodeBlock(blks[i],blks[0][2]);
					var code:String = (b.type=="obj"?b.code.code:b.code);
					funcCode+=code+"\n";
				}
			}
			funcCode+="}\n";
			funcList.push({name:funcName,code:funcCode});
		}
		private function parseIfElse(blk:Object):String{
			var codeIfElse:String = ""
			var logiccode:CodeBlock = getCodeBlock(blk[1]);
			codeIfElse+=StringUtil.substitute("if({0}){\n",logiccode.type=="obj"?logiccode.code.code:logiccode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:CodeBlock = getCodeBlock(blk[2][i]);
					var ifcode:String=(b.type=="obj"?b.code.code:b.code)+""
					codeIfElse+=ifcode
				}
			}
			codeIfElse+="}else{\n";
			if(blk[3]!=null){
				for(i=0;i<blk[3].length;i++){
					b = getCodeBlock(blk[3][i]);
					var elsecode:String=(b.type=="obj"?b.code.code:b.code)+"";
					codeIfElse+=elsecode;
				}
			}
			codeIfElse+="}\n"
			return codeIfElse
		}
		
		private function parseIf(blk:Object):String{
			var codeIf:String = ""
			var logiccode:String = getCodeBlock(blk[1]).code;
			codeIf+=StringUtil.substitute("if({0}){\n",logiccode)
			if(blk is Array){
				if(blk.length>2){
					if(blk[2]!=null){
						for(var i:int=0;i<blk[2].length;i++){
							var b:CodeBlock = getCodeBlock(blk[2][i]);
							var ifcode:String=(b.type=="obj"?b.code.code:b.code)+"";
							codeIf+=ifcode;
						}
					}
				}
			}
			codeIf+="}\n"
			return codeIf
		}
		
		private function parseVarWrite(blk:Object):String{
			var varName:String = blk[2]
			if (varList.indexOf(varName)==-1){
				varList.push(varName)
			}
			if (varListWrite.indexOf(varName)==-1){
				varListWrite.push(varName)
			}	
			return ""
		}
		private function parseComputeFunction(blk:Object):String{
			var cBlk:CodeBlock = getCodeBlock(blk[2]);
			if(blk[1]=="10 ^"){
				return StringUtil.substitute("pow(10,{0})",cBlk.code);
			}else if(blk[1]=="e ^"){
				return StringUtil.substitute("exp({0})",cBlk.code);
			}else if(blk[1]=="ceiling"){
				return StringUtil.substitute("ceil({0})",cBlk.code);
			}else if(blk[1]=="log"){
				return StringUtil.substitute("log10({0})",cBlk.code);
			}else if(blk[1]=="ln"){
				return StringUtil.substitute("log({0})",cBlk.code);
			}
			
			return StringUtil.substitute("{0}({1})",getCodeBlock(blk[1]).code,cBlk.code).split("sin(").join("sin(angle_rad*").split("cos(").join("cos(angle_rad*").split("tan(").join("tan(angle_rad*");
		}
		private function buildCode(modtype:String,iotype:String,modport:*,modslot:*,valuestring:*):Object{
			var workcode:String = ""
			var setupcode:String = ""
			var defcode:String = ""    
			var inccode:String = ""
			var loopcode:String = ""
			var portcode:String = modport is CodeObj?modport.code:modport;
			var slotcode:String = modslot is CodeObj?modslot.code:modslot;
			var valuecode:String = valuestring is CodeObj?valuestring.code:valuestring;
			if(modtype=="available"){
				if(iotype=="serial"){
					setupcode = StringUtil.substitute("Serial.begin(115200);\n")
					workcode=StringUtil.substitute("dataLineAvailable()");
				}
			}else if(modtype=="read"){
				if(iotype=="serial"){
					setupcode = StringUtil.substitute("Serial.begin(115200);\n")
					workcode=StringUtil.substitute("readDataLine()");
				}
			}else if(modtype=="write"){
				if(iotype=="serial"){
					setupcode = StringUtil.substitute("Serial.begin(115200);\n");
					if(modslot=="command"){
						workcode = StringUtil.substitute("Serial.print(\"{0}=\");Serial.println({1});\n",portcode,valuecode);
					}else if(modslot=="update"){
						workcode = StringUtil.substitute("updateVar(\"{0}\",&{1});\n",portcode,portcode);
					}else{
						workcode=StringUtil.substitute("Serial.println("+(modport is CodeObj?"{0}":"\"{0}\"")+");\n",portcode);
					}
				}
			}else if(modtype=="clear"){
				
			}else{
				hasUnknownCode = true;
				trace("Unknow Module:"+modtype)
			}
			var codeObj:Object = {setup:setupcode,work:workcode,def:defcode,inc:inccode,loop:loopcode};		
			return codeObj;
		}
		
		private function buildModule(mname:String,mport:*,mslot:*,mtype:String,mindex:int,mvalue:*):Object{
			var modDict:Object = {name:mname,port:mport,slot:mslot,type:mtype,index:mindex,value:mvalue}
			modDict.code = buildCode(mname,mtype,mport,mslot,mvalue)
			return modDict;
		}

		private function appendFun(funcode:*):void{
			//			if (c!="\n" && c!="}")
			//funcode+=";\n"
			var allowAdd:Boolean = funcode is CodeObj;
			funcode = funcode is CodeObj?funcode.code:funcode;
			
			if(funcode==null) return;
			if(funcode.length==0) return;
			var c:String =  funcode.charAt(funcode.length-1)
			if(ccode_pointer=="setup"){
				ccode_setup_fun += funcode;
				//解决连续两条设置变量的指令在Arduino下会被过滤的bug 这里貌似不需要去重处理，只要setup里面的代码保持初始化一次，后面work的代码应该可以多次出现 20161121
				/*if((ccode_setup.indexOf(funcode)==-1&&ccode_setup_fun.indexOf(funcode)==-1)||funcode.indexOf("delay")>-1||allowAdd){
//					if((funcode.indexOf(" = ")>-1&&funcode.indexOf("drawTemp")==-1&&funcode.indexOf("lastTime = ")==-1)&&funcode.indexOf("while")==-1&&funcode.indexOf("for")==-1){
//						ccode_setup_def = funcode + ccode_setup_def;
//					}else{
						ccode_setup_fun += funcode;
//					}
				}*/
			}
			else if(ccode_pointer=="loop"){
				ccode_loop+=funcode;
			}
		}
		
		private function getCodeBlock(blk:Object,params:Array=null,  parsingParams:Boolean= false):CodeBlock{
			var code:CodeObj;
			var codeBlock:CodeBlock = new CodeBlock;
			if(blk==null||blk==""){
				codeBlock.type = "number";
				codeBlock.code = "0";
				return codeBlock;
			}
			if(!(blk is Array)){
				codeBlock.code = ""+blk;
				codeBlock.type = isNaN(Number(blk))?"string":"number";
				return codeBlock;
			}
			/*if(blk.length==0){
				codeBlock.type = "string";
				codeBlock.code = "";
				return codeBlock;
			}else if(blk.length==16){     // *JC* else if(blk.length==16){
				codeBlock.type = "array";
				codeBlock.code = blk;
				return codeBlock;
			}*/
			if(mathOp.indexOf(blk[0])>=0){
				codeBlock.type = "obj";
				codeBlock.code = parseMath(blk);
				return codeBlock;
			}
			else if(blk[0]=="readVariable"){
				codeBlock.type = "obj";
				codeBlock.code = parseVarRead(blk);
				return codeBlock;
			}
			else if(blk[0]=="initVar:to:"){
				codeBlock.type = "obj";
				codeBlock.code = null;
				var tmpCodeBlock:Object = {code:{setup:parseVarSet(blk),work:"",def:"",inc:"",loop:""}}
				moduleList.push(tmpCodeBlock);
				return codeBlock;
			}
			else if(blk[0]=="setVar:to:"){
				codeBlock.type = "string";
				codeBlock.code = parseVarSet(blk);
				return codeBlock;
			}
			else if(blk[0]=="readVariable:")
				code = parseVarShow(blk);
			else if(blk[0]=="wait:elapsed:from:"){
				codeBlock.type = "string";
				codeBlock.code = parseDelay(blk);
				return codeBlock;
			}
			else if(blk[0]=="append:toList:"){
				codeBlock.type = "string";
				codeBlock.code = parseArraySet(blk);
				return codeBlock;
			}
			else if(blk[0]=="deleteLine:ofList:"){
				codeBlock.type = "string";
				codeBlock.code = parseArrayDelete(blk);
				return codeBlock;
			}
			else if(blk[0]=="insert:at:ofList:"){
				codeBlock.type = "string";
				codeBlock.code = parseArrayInsertAt(blk);
				return codeBlock;
			}
			else if(blk[0]=="setLine:ofList:to:"){
				codeBlock.type = "string";
				codeBlock.code = parseArrayReplace(blk);
				return codeBlock;
			}
			else if(blk[0]=="getLine:ofList:"){
				codeBlock.type = "obj";
				codeBlock.code = parseArrayGet(blk);
				return codeBlock;
			}else if(blk[0]=="lineCountOfList:"){
				codeBlock.type = "number";
				codeBlock.code = parseArrayLength(blk);
				return codeBlock;
			}else if(blk[0]=="list:contains:"){
				codeBlock.type = "number";
				codeBlock.code = parseArrayContains(blk);
				return codeBlock;
			}
			
			
			else if(blk[0]=="doIfElse"){
				codeBlock.type = "string";
				codeBlock.code = parseIfElse(blk);
				return codeBlock;
			}
			else if(blk[0]=="doIf"){
				codeBlock.type = "string";
				codeBlock.code = parseIf(blk);
				return codeBlock;
			}
			else if(blk[0]=="writeVariable:")
			{
				codeBlock.type = "string";
				codeBlock.code = parseVarWrite(blk);
				return codeBlock;
			}
			else if(blk[0]=="doRepeat"){
				codeBlock.type = "string";
				codeBlock.code = parseDoRepeat(blk);
				return codeBlock;
			}/*else if(blk[0]=="doForever"){
				codeBlock.type = "string";
				codeBlock.code = parseForever(blk);
				return codeBlock;
			}*/else if(blk[0]=="doWaitUntil"){
				codeBlock.type = "string";
				codeBlock.code = parseDoWaitUntil(blk);
				return codeBlock;
			}else if(blk[0]=="doUntil"){
				codeBlock.type = "string";
				codeBlock.code = parseDoUntil(blk);
				return codeBlock;
			}else if(blk[0]=="call"){
				codeBlock.type = "obj";//修复新建的模块指令函数，无法重复调用
				codeBlock.code = new CodeObj(parseCall(blk));
				return codeBlock;
			}else if(blk[0]=="randomFrom:to:"){
				codeBlock.type = "number";
				//as same as scratch, include max value
				codeBlock.code = StringUtil.substitute("random({0},({1})+1)",getCodeBlock(blk[1]).code,getCodeBlock(blk[2]).code);
				return codeBlock;
			}else if(blk[0]=="computeFunction:of:"){
				codeBlock.type = "number";
				codeBlock.code = parseComputeFunction(blk);
				return codeBlock;
			}else if(blk[0]=="concatenate:with:"){
				var s1:CodeBlock = getCodeBlock(blk[1]);
				var s2:CodeBlock = getCodeBlock(blk[2]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("{0}+{1}",(s1.type=="obj")?s1.code.code:"String(\""+s1.code+"\")",(s2.type=="obj")?s2.code.code:"String(\""+s2.code+"\")"));
				return codeBlock;
			}else if(blk[0]=="letter:of:"){
				s2 = getCodeBlock(blk[2]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("{1}.charAt({0}-1)",getCodeBlock(blk[1]).code,(s2.type=="obj")?"String("+s2.code.code+")":"String(\""+s2.code+"\")"));
				return codeBlock;
			}else if(blk[0]=="castDigitToString:"){
				codeBlock.type = "string";
				codeBlock.code = new CodeObj(StringUtil.substitute('String({0})',getCodeBlock(blk[1]).code));
				return codeBlock;
			}else if(blk[0]=="stringLength:"){
				s1 = getCodeBlock(blk[1]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("String({0}).length()",(s1.type != "obj")?"\""+s1.code+"\"":s1.code.code));
				return codeBlock;
			}else if(blk[0]=="mapFunction:"){
				s1 = getCodeBlock(blk[1]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("map({0},{1},{2},{3},{4})", getCodeBlock(blk[1]).code, getCodeBlock(blk[2]).code, getCodeBlock(blk[3]).code, getCodeBlock(blk[4]).code, getCodeBlock(blk[5]).code )  );
				return codeBlock;
			}else if(blk[0]=="changeVar:by:"){
				codeBlock.type = "string";
				codeBlock.code = StringUtil.substitute("{0} += {1};\n",getCodeBlock(castVarName(blk[1])).code,getCodeBlock(blk[2]).code);
				return codeBlock;
			} 
			
	
			else{
				var objs:Array = eBlock.app.extensionManager.specForCmd(blk[0]);
				
				
				if(objs!=null){
					var obj:Object = objs[objs.length-1];
					obj = obj[obj.length-1];
					if(typeof obj == "object"){
						var ext:ScratchExtension = eBlock.app.extensionManager.extensionByName(blk[0].split(".")[0]);
						var codeObj:Object = {code:{setup:substitute(obj.setup,blk as Array,ext),work:substitute(obj.work,blk as Array,ext),def:substitute(obj.def,blk as Array,ext),inc:substitute(obj.inc,blk as Array,ext),loop:substitute(obj.loop,blk as Array,ext)}};	
						if(!availableBlock(codeObj)){
							if(ext!=null){
								if(srcDocuments.indexOf(ext.srcPath)==-1){
									srcDocuments.push(ext.srcPath);
								}
							}
							moduleList.push(codeObj);  //*JC* almacena los includes y defs para que no se repitan
						}
						codeBlock.type = "obj";
						codeBlock.code = new CodeObj(codeObj.code.work);
						return codeBlock;
					}
				}else{
					
						trace("BG:  NULL");
					
				}
				
				
				var b:Block = BlockIO.arrayToStack([blk]);
				if(b.op=="getParam"){
					codeBlock.type = "number";
					codeBlock.code = castVarName(b.spec.split(" ").join("_"));
					return codeBlock;
				}
				if(b.op=="procDef" )  {  
					return codeBlock;
				}
				unknownBlocks.push(b);
				hasUnknownCode = true;
				codeBlock.type = "string";
				codeBlock.code = StringUtil.substitute("//unknow {0}{1}",blk[0],b.type=='r'?"":"\n");
				return codeBlock;
			}
			codeBlock.type = "obj";
			codeBlock.code = code;
			return codeBlock;
		}  
		private function substitute(str:String,params:Array,ext:ScratchExtension=null,offset:uint = 1):String{
	 	
			if(str=="" || str==null) return "";
			
			
			
			
			for(var i:uint=0;i<params.length-offset;i++){
				var o:CodeBlock = getCodeBlock(params[i+offset], null, true);
				
				var menu_key:String=""; //*JC* el parámetro es un valor con menu en la extension y puede que queramos usar el nombre de la variable en lugar de su valor ( si lo usamos con  {{0}}  en lugar de {0} )
				
				//满足下面的条件则不作字符替换处理
				if(str.indexOf("ir.sendString")>-1 || (str.indexOf(".drawStr(")>-1 && i==3))
				{
					var v:*=o.code;
	    		}
				else
				{

					v=o.type=="string"?(ext.values[o.code]==undefined?o.code:ext.values[o.code]):null;
					menu_key = o.code;
								

					
				}
				
				//*JC*  mostrar a matriz en binario
				if(params[0].indexOf("showPixels")>-1  ){

					str = str.split("{"+i+"}").join(  LightSensor2.getSourceCode(o.code)   );
					continue;
					
				}
				
				//var s:CodeBlock = new CodeBlock();
				var s:CodeBlock = o;  //*JC* optimizacion 
				if(ext==null||(v==null||v==undefined)){
					
					//s = getCodeBlock(params[i+offset]); //*JC* optimizacion  ya se recoge lo mismo al inicio del bucle, no hay que volver a calcularlo
					s.type = (s.type=="obj"&&s.code.type!="code")?"string":"number";
					
				}else if( s.type=="obj" && s.code.type=="code" ){  //*JC*  string variable string
					str = str.split("{"+i+"}").join("String("+s.code.code+").c_str()");
					continue;
				}else{
					
					s.type = isNaN(Number(v))?"string":"number";
					s.code = v;

				}
				if((s.code==""||s.code==" ")&&s.code!=0&&s.type == "number"){
					s.type = "string";
				}
				if(str.indexOf(".drawStr(")>-1){
					if(i==3 && (s.type == "number" || s.type == "code")  ){
						if(s.code is String){
							s.type = "string";
						}else if(s.code is CodeObj){
							str = str.split("{"+i+"}").join("String("+s.code.code+").c_str()");
							continue;
						}
					}
				}else if(str.indexOf("ir.sendString(") == 0){
					if(s.type == "number" && s.code is String){
						s.type = "string";
					}
				}
				/*if(str.indexOf("se.equalString")>-1) 
				{
					s.type = "string";
				}*/
				//如果用到通讯模块的=号，那么将数字也转为字符串进行比较，否则报错
				if(str.indexOf("se.equalString")>-1)
				{
					str = str.split("{"+i+"}").join(( s.type == "string"||!isNaN(Number(s.code)))?('"'+s.code+'"'):(( s.type == "number")?s.code:s.code.code));
				}else{
						
					str = str.split("{"+i+"}").join(( s.type == "string")?  ('"'+s.code+'"')  :  (( s.type == "number")?s.code:s.code.code)  );
				}
				
			}
			return str;
		}
		private function availableBlock(obj:Object):Boolean{
			for each(var o:Object in moduleList){
				if(  ( o.code.def!=""&&o.code.setup!="" ) &&   o.code.def==obj.code.def&&o.code.setup==obj.code.setup){
					return true;
				}
			}
			return false;
		}
		private function parseLoop(blks:Object):void{
			ccode_pointer="loop";
			if(blks!=null){
				for(var i:int;i<blks.length;i++){
					var b:Object = blks[i]
					var cBlk:CodeBlock = getCodeBlock(b);
					appendFun(cBlk.code);
				}
			}
		}
		private function parseModules(blks:Object):void{
			var isArduinoCode:Boolean = false;
			for(var i:int;i<blks.length;i++){
				var b:Object = blks[i];
				var objs:Array = eBlock.app.extensionManager.specForCmd(blks[0]);
				if(objs!=null){
					var obj:Object = objs[objs.length-1];
					obj = obj[obj.length-1];
					if(typeof obj == "object"&&obj!=null){
						var codeObj:Object = {code:{setup:obj.setup,work:obj.work,def:obj.def,inc:obj.inc,loop:obj.loop}};	
						moduleList.push(codeObj);
					}
				}
			}
		} 
		private function parseCodeBlocks(blks:Object):Boolean{
			var isArduinoCode:Boolean = false;
			for(var i:int;i<blks.length;i++){
				var b:Object = blks[i];
				var op:String = b[0];
				if(op.indexOf("runArduino")>-1 || op.indexOf("when")>-1 ){ //whenButtonPressed
					ccode_pointer="setup";
					isArduinoCode = true;
					
					var objs:Array = eBlock.app.extensionManager.specForCmd(op);
					var ext:ScratchExtension = eBlock.app.extensionManager.extensionByName(op.split(".")[0]);
					if(ext!=null){
						if(srcDocuments.indexOf(ext.srcPath)==-1){
							srcDocuments.push(ext.srcPath);
						}
					}
					if(objs!=null){
						var obj:Object = objs[objs.length-1];
						obj = obj[obj.length-1];
						if(typeof obj == "object"&&obj!=null){
							var codeObj:Object = {code:{setup:obj.setup,work:obj.work,def:obj.def,inc:obj.inc,loop:obj.loop}};	
							moduleList.push(codeObj);
						}
					}
				}else if(op=="doForever" || op=="doForeverHat"){
					ccode_pointer="loop";
					parseLoop(b[1]);
				}else{
					var cBlk:CodeBlock = getCodeBlock(b);
					appendFun(cBlk.code);
				}
			}
			return isArduinoCode;
		}
		
		private function buildSerialParser(code:String):String{
			if(varListWrite.length==0){
				code = code.replace("//serialParserCall","").replace("//serialParser","")
				return code;
			}
			var codeParser:String=""
			for(var i:int=0;i<varListWrite.length;i++){
				var p:String = varListWrite[i]
				codeParser+=codeSerialScanf.replace("param", p)
			}			
			codeParser = codeSerialParser.replace("//parseList", codeParser)
			code = code.replace("//serialParserCall","parseSerialInput();").replace("//serialParser",codeParser);
			return code;
		}
		
		private function fixTabs(code:String):String{
			var tmp:String = "";
			var tabindex:int=0
			var newLineList:Array = []
			var lines:Array = code.split('\n')
			for(var i:int=0;i<lines.length;i++){
				var l:String = lines[i]
				if(l.indexOf("}")>=0)
					tabindex-=1
				tmp = ""
				for(var j:int=0;j<tabindex;j++)
					tmp+="    "
				newLineList.push(tmp+l)
				if(l.indexOf("{")>=0)
					tabindex+=1
			}
			code = newLineList.join("\n")
			code = code.replace(new RegExp("\r\n", "gi"),"\n") // replace windows type end line
			return code;
		}
		private function fixVars(code:String):String{
						
			for each(var s:String in varStringList){
				code = code.split("double " +s).join("String "+s);
			}
			return code;
		}
		private var requiredCpp:Array=[];
		public function jsonToCpp(code:String):String{
			// reset code buffers 
			ccode_setup=""
			ccode_setup_fun = "";
//			ccode_setup_def = "";
			ccode_loop=""
			ccode_inc=""
			ccode_def=""
			ccode_func="";
			hasUnknownCode = false;
			// reset arrays
			arrayList=[];
			arrayStringList=[];
			varList=[];
			varStringList=[];
			varListWrite=[]
			paramList=[]
			moduleList=[]
			funcList = [];
			unknownBlocks = [];
			// params for compiler
			requiredCpp=[];
			var buildSuccess:Boolean = false;
			var objs:Object = util.JSON.parse(code);
			var childs:Array = objs.children.reverse();
			for(var i:int=0;i<childs.length;i++){
				buildSuccess = parseScripts(childs[i].scripts);
			}
			if(!buildSuccess){
				parseScripts(objs.scripts);
			}
			ccode_func+=buildFunctions();
			ccode_setup = hackVaribleWithPinMode(ccode_setup);
			
			var useTemplate:String = codeTemplate; //*JC* usamos custom template si la placa tiene uno "template.c"
			if( DeviceManager.sharedManager().selectedBoard.template ) useTemplate = DeviceManager.sharedManager().selectedBoard.template;
			
			var retcode:String = useTemplate.replace("//setup",ccode_setup).replace("//loop", ccode_loop).replace("//define", ccode_def).replace("//include", ccode_inc).replace("//function",ccode_func);
			retcode = retcode.replace("//_loop", ccode_loop2);
			retcode = buildSerialParser(retcode);
			retcode = fixTabs(retcode);
			retcode = fixVars(retcode);
			//由于2.4G手柄，不同主板的接口不一样，所以在这里修正一下port口
			if(retcode.indexOf("MePS2 MePS2(PORT)")>-1)
			{
				if(DeviceManager.sharedManager().selectedBoard.label.indexOf( "Mega Pi") >-1 )
				{
					retcode = retcode.replace("MePS2 MePS2(PORT)","MePS2 MePS2(PORT_15)");
				}
				else if(DeviceManager.sharedManager().selectedBoard.label.indexOf( "Auriga")>-1 )
				{
					retcode = retcode.replace("MePS2 MePS2(PORT)","MePS2 MePS2(PORT_16)");
				}
				else if(DeviceManager.sharedManager().selectedBoard.label.indexOf("mBot")>-1 )
				{
					retcode = retcode.replace("MePS2 MePS2(PORT)","MePS2 MePS2(PORT_5)");
				}
			}
			
			//requiredCpp = getRequiredCpp()
			// now go into compile process
			if(!NativeProcess.isSupported) return "";
			return (retcode);
			//			buildAll(retcode, requiredCpp);
		}
		
		// HACK: 在Arduino模式下，如果你定义一个变量，设置一个变量，并对其进行IO操作，
		// 该变量会在pinMode语句之后被设置。
		// 这会导致pinMode语句中变量未初始化的问题。
		private function hackVaribleWithPinMode(originalCode:String):String
		{
			var lines:Array= originalCode.split("\n");
			var collectedPinModes:Array = [];
			var line:String;
			// collect all pinMode commands
			for(var i:int=0; i<lines.length; i++) {
				line = lines[i];
				if( line.indexOf("pinMode") != -1 || line.indexOf("// init pin") != -1 ) {
					var sliced:Array = lines.splice(i, 1);
					collectedPinModes = collectedPinModes.concat(sliced);
					i = i-1;
				}
			}
			
			if(collectedPinModes.length == 0){
				return originalCode;
			}
			
			// put pinMode command just before io commands
			for(i=0; i<lines.length; i++) {
				line = lines[i];
				if(line.indexOf("digitalWrite")!=-1 || line.indexOf("digitalRead")!=-1 || line.indexOf("pulseIn")!=-1 || 
					line.indexOf("if(")!=-1 || line.indexOf("for(")!=-1 || line.indexOf("while(")!=-1 || 
					line.indexOf("analogWrite")!=-1 || line.indexOf("analogWrite")!=-1 || line.indexOf("// write to")!=-1) {
					break;
				}
			}
			var linesBefore:Array = lines.splice(0, i);
			lines = linesBefore.concat(collectedPinModes, lines);
				
			var joinedLines:String = lines.join("\n");
			return joinedLines;
		}
		
		private function parseScripts(scripts:Object):Boolean
		{
			if(null == scripts){
				return false;
			}  
			var result:Boolean = false;
			for(var j:uint=0;j<scripts.length;j++){
				var scr:Object = scripts[j][2];
			 	
				var blkName:String ="";
				var extName:String ="";
				if(scr[0][0].indexOf(".")>0){
					blkName = scr[0][0].split(".")[1];//- me quedo con el nombre de la funcion mbot.func = "whenButton"
					extName = scr[0][0].split(".")[0];
				}else{
					blkName = scr[0][0];
				}
				 
				
				///whenButtonPressed/
				if(blkName.indexOf("when")>-1){  //*JC* para que se trate de la misma forma que un procedimiento nuevo
					
				    var scr_copy:Array; 
					/*clono el arrat*/
					var ba:ByteArray = new ByteArray(); 
					ba.writeObject(scr); // Copy the original array (a) into a ByteArray instance
					ba.position = 0; // Put the cursor at the beginning of the ByteArray to read it
					scr_copy = ba.readObject(); // Store a copy of the array in the destination array (b)
					ba.clear(); 
					 
					 
					//- unir cada parámetro al nombre de la función   whenButton "pressed"  = whenButton_pressed
					var numParams:int =scr_copy[0].length;
					var currParam:String="";
					for(var p:int=1;p<numParams; p++){
						currParam = scr_copy[0][1];
						//currParam = currParam.replace([' ', '>', '<', '='], ['_', 'gt','lg', 'eq']);
						currParam = currParam.replace(" ", "_").replace("=", "eq").replace(">", "gt").replace("<", "lt").replace("-", "_").replace("/", "_");
						blkName+="_"+currParam;
						scr_copy[0].splice(1, 1); //- elimino este parametro
					}
					
					scr_copy[0][0]= blkName +" %8";
					scr_copy[0].push( ["evt"]);
		 								
					scr_copy[0].unshift("procDef");  //- lo convierto en un bloque de procedimiento de scratch
					 
					var callbackId:int=eBlock.app.extensionManager.getCallbackId(extName, blkName);
					
					//- registramos el callback 
					//var cbCode:Object = {code:{setup:"register_callback(" +blkName.toUpperCase()+"_CALLBACK, " +blkName+");\n"  ,work:"",def:""  ,inc:"",loop:""}}
					
					var cbCode:Object = {code:{setup:"register_callback("+callbackId +", " +blkName+");\n"  ,work:"",def:""  ,inc:"",loop:""}}
						
					moduleList.push(cbCode);
					  
				 	
					addFunction(scr_copy as Array);
					parseModules(scr_copy);
					getCodeBlock(scr[0]);
					buildCodes();
				
				}else if(blkName=="procDef"  ){  //*JC*
					addFunction(scr as Array);
					parseModules(scr);
					buildCodes();
				}
			}
			for(j=0;j<scripts.length;j++){
				scr = scripts[j][2];
				/*if(scr[0][0].indexOf("whenButtonPressed") > 0)
				{
					getCodeBlock(scr[0]);
				}*/
				if(scr[0][0].indexOf("runArduino") < 0  &&  scr[0][0].indexOf("doForeverHat") < 0){
					continue;
				}//选中的Arduino主代码
				
				if(!parseCodeBlocks(scr)){
					continue;
				}
				buildCodes();

				result = true;
				//break; // only the first entrance is parsed
			}
			if(_scratch!=null){
				_scratch.dispatchEvent(new RobotEvent(RobotEvent.CCODE_GOT,""));
			}
			return result;
		}
		private function buildCodes():void{
			buildInclude();			
			buildDefine();
			buildSetup();
//			ccode_setup+=ccode_setup_def;
			//buildSetup();
			ccode_setup+=ccode_setup_fun;
			ccode_setup_fun = "";
			ccode_loop2=buildLoopMaintance();
		}
		private function buildSetup():String{
			var modInitCode:String = "";
			for(var i:int=0;i<moduleList.length;i++){
				var m:Object = moduleList[i];
				var code:* = m["code"]["setup"];
				code = code is CodeObj?code.code:code;
				if(code!=""){
					if(ccode_setup.indexOf(code)==-1&&ccode_setup_fun.indexOf(code)==-1){
						ccode_setup+=code+"";
					}
				}
			}

			return modInitCode;
		}
		static private const varNamePattern:RegExp = /^[_A-Za-z][_A-Za-z0-9]*$/;
		static private function castVarName(name:String, isFunction:Boolean=false):String
		{
			if(varNamePattern.test(name)){
				return name;
			}
			var newName:String = isFunction ? "__func_" : "__var_";
			for(var i:int=0; i<name.length; ++i){
				newName += "_" + name.charCodeAt(i).toString();
			}
			return newName;
		}
		
		private function buildDefine():String{
			var modDefineCode:String = ""
			for(var i:int=0;i<varList.length;i++){
				var v:String = varList[i];
				var code:* = StringUtil.substitute("double {0};\n" ,castVarName(v))
				if(ccode_def.indexOf(code)==-1){
					ccode_def+=code;
				}
			}
			
			for(i=0;i<arrayList.length;i++){   //*JC*
				v = arrayList[i];
				if(arrayStringList.indexOf(castVarName(v))>-1){
					code = StringUtil.substitute("List<String> {0};\n" ,castVarName(v))	
				}else{
					code = StringUtil.substitute("List<double> {0};\n" ,castVarName(v))
				}
				
				if(ccode_def.indexOf(code)==-1){
					ccode_def+=code;
				}
			}
			
			for(i=0;i<moduleList.length;i++){
				var m:Object = moduleList[i]
				code = m["code"]["def"];
				code = code is CodeObj?code.code:code;
				if(code!=""){
					if(code.indexOf("--separator--")>-1)
					{
						//以--separator--分割，以代码块为单位进行去重
						var categoryArr:Array = code.split("--separator--");
						for(var k:int=0;k<categoryArr.length;k++)
						{
							var array:Array = categoryArr[k].split("\n");
							var tmpCode_def:String = "";
							for(var j:int=0;j<array.length;j++){
								if(!Boolean(array[j])){
									continue;
								}
								
								tmpCode_def+=array[j]+"\n";
								
								//ccode_def+=array[j]+"\n";
							}
							if(ccode_def.indexOf(tmpCode_def)<0)
							{
								ccode_def+=tmpCode_def;
							}
						}
					}
					else
					{
						//按行分割，进行去重
						array = code.split("\n");
						for(k=0;k<array.length;k++)
						{
							if(ccode_def.indexOf(array[k])<0)
							{
								ccode_def+=array[k]+"\n";
							}
						}
						
					}
					
					
				}
			}
			
			return modDefineCode;
		}
		
		private function buildInclude():String{
			var modIncudeCode:String = ""
			for(var i:int=0;i<moduleList.length;i++){
				var m:Object = moduleList[i]
				var code:* = m["code"]["inc"];
				code = code is CodeObj?code.code:code;
				if(code!=""){
					if(ccode_inc.indexOf(code)==-1)
						if(code.indexOf("#include")>-1)
						{
							ccode_inc = code+ccode_inc;
						}
						else
						{
							ccode_inc += code;
						}
						//ccode_inc += code;
				}
			}
			
			return modIncudeCode;
		}
		
		private function buildLoopMaintance():String{
			var modMaintanceCode:String = ""
			for(var i:int=0;i<moduleList.length;i++){
				var m:Object = moduleList[i]
				var code:* = m["code"]["loop"];
				code = code is CodeObj?code.code:code;
				if(code!=""){
					if(modMaintanceCode.indexOf(code)==-1){
						modMaintanceCode+=code+"\n";
					}
				}
			}
			return modMaintanceCode
		}
		private function buildFunctions():String{
			var funcCodes:String = ""
			for(var i:int=0;i<funcList.length;i++){
				var m:Object = funcList[i]
				var code:* = m["code"];
				code = code is CodeObj?code.code:code;
				if(code!=""){
					if(funcCodes.indexOf(code)==-1)
						funcCodes+=code+"\n";
				}
			}
			return funcCodes;
		}
		private function getRequiredCpp():Array{
			return [];
		}
		/*
		public function uploadCode(code:String):void{
			var url:String = "http://192.168.1.251:8080/";
			var request:URLRequest = new URLRequest(url);
			var requestVars:URLVariables = new URLVariables();
			requestVars.code = code;
			requestVars.sessionTime = new Date().getTime();
			request.data = requestVars;
			request.method = URLRequestMethod.POST;
			
			var urlLoader:URLLoader = new URLLoader();
			urlLoader = new URLLoader();
			urlLoader.dataFormat = URLLoaderDataFormat.TEXT;
			urlLoader.addEventListener(Event.COMPLETE, uploadCompleteHandler,false,0,true);
			urlLoader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler, false, 0, true);
			
			try{
				urlLoader.load(request);
			}catch(e:Error){
				trace(e);
			}
			
		}
		*/
		private function saveHexFile(token:String,hexString:String):void{
			var f:File = new File();
			f.addEventListener(Event.COMPLETE, _onRfComplete);
			f.save(hexString,token+".hex");
		}
		
		private function _onRfComplete(e:Event):void{
			hexPath = e.target.nativePath
			_scratch.dispatchEvent(new RobotEvent(RobotEvent.HEX_SAVED,hexPath));
		}
		
		private function uploadCompleteHandler(e:Event):void{
			var response:String = String(e.target.data);
			//trace("response:"+response);
			jsonObj = util.JSON.parse(response);
			hexCode = jsonObj["hex"]
			ccode = jsonObj["code"]
			token = jsonObj["hash"]
			output = jsonObj["output"]
			_scratch.dispatchEvent(new RobotEvent(RobotEvent.CCODE_GOT,ccode));
			_scratch.dispatchEvent(new RobotEvent(RobotEvent.COMPILE_OUTPUT,output));
			if(hexCode)
				saveHexFile(token,hexCode);
		}
		
		private function ioErrorHandler(e:Event):void{
			
		}
		
		
		
		
		/****** *****************************
		 * compiler ralated functions 
		 * **********************************/
		
		
		
		private var tc_projCpp:*;
		private var tc_workdir:*;
		private var tc_cppList:*;
		private var nativeDoneEvent:String;
		private var nativeWorkList:Array=[];
		private var srcDocuments:Array = [];
		private var numOfProcess:uint = 0;
		private var numOfSuccess:uint = 0;
		private var _projectDocumentName:String = "";
		private function prepareProjectDir(ccode:String):void{
//			_currentDevice = DeviceManager.sharedManager().currentDevice;
			
			var cppList:Array =  requiredCpp;
			// get building direcotry ready
			var workdir:File = File.applicationStorageDirectory.resolvePath("scratchTemp");
			if(!workdir.exists){
				workdir.createDirectory(); 
			}
			//			var srcdir:File = File.applicationDirectory.resolvePath("compiler"); 
			if(!workdir.exists){
				return;
			}
			// copy firmware directory
			workdir = workdir.resolvePath(projectDocumentName);
//			var srcdir:File = ApplicationManager.sharedManager().documents.resolvePath("mBlock/libraries/"+_extSrcPath+"/src");
//			if(srcdir.exists && srcdir.getDirectoryListing().length > 0){
//				srcdir.copyTo(workdir,true);
//			}
			//*
			for each(var path:String in srcDocuments){
				var srcdir:File = new File(path);
				if(srcdir.exists && srcdir.isDirectory){
					copyCompileFiles(srcdir.getDirectoryListing(),workdir);
				}
			}
			//*/
			var projCpp:File = File.applicationStorageDirectory.resolvePath("scratchTemp/"+projectDocumentName+"/"+projectDocumentName+".ino")
			LogManager.sharedManager().log("projCpp:"+projCpp.nativePath);
			var outStream:FileStream = new FileStream();
			outStream.open(projCpp, FileMode.WRITE);
			outStream.writeUTFBytes(ccode)
			outStream.close()
			if(ccode.indexOf("updateVar")>-1){
				// aux ino file for serial variable parser
				projCpp = File.applicationStorageDirectory.resolvePath("scratchTemp/"+projectDocumentName+"/MeComm.ino")
				outStream = new FileStream();
				outStream.open(projCpp, FileMode.WRITE);
				outStream.writeUTFBytes(serialParserInoFile)
				outStream.close()
			}
			
			projectPath = workdir.nativePath;
			LogManager.sharedManager().log("projectPath:"+projectPath);
		}
		
	
		private var compileErr:Boolean = false;
		//*
		private function copyCompileFiles(files:Array, workdir:File):void
		{
			for(var i:int = 0; i < files.length; ++i){
				var file:File = files[i];
				switch(file.extension){
					case "cpp":
					case "c":{
						var fileName:String = file.name.split(".")[0];
						if(requiredCpp.indexOf(fileName) < 0){
							requiredCpp.push(fileName);
						}
					}
						//fall through
					case "h":
						file.copyTo(workdir.resolvePath(file.name), true);
						break;
				}
			}
		}
		//*/
		private function get projectDocumentName():String{
			var now:Date = new Date;
			var pName:String = eBlock.app.projectName().split(" ").join("").split("(").join("").split(")").join("");
			//用正则表达式来过滤非法字符
			var reg:RegExp = /[^A-z0-9]|^_/g;
			pName = pName.replace(reg,"_");
			/*for(var i:uint=0;i<pName.length;i++){
				if(pName.charCodeAt(i)>100){
					pName = pName.split(pName.charAt(i)).join("_");
				}
			}*/
			_projectDocumentName = "project_"+pName+ (now.getMonth()+"_"+now.getDay());
			if(_projectDocumentName=="project_"){
				_projectDocumentName = "project";
			}
			return _projectDocumentName;
		}
		public function buildAll(ccode:String):String
		{
			if(isUploading){
				return "uploading";
			}

			// get building direcotry ready
			var workdir:File = File.applicationStorageDirectory.resolvePath("scratchTemp")
			if(!workdir.exists){
				workdir.createDirectory(); 
			}  
			
			if(!workdir.exists){
				return "workdir not exists";
			}
			nativeWorkList = []
			// copy firmware directory
			workdir = workdir.resolvePath(projectDocumentName);
//			var srcdir:File = ApplicationManager.sharedManager().documents.resolvePath("mBlock/libraries/"+_extSrcPath+"/src");
//			if(srcdir.exists && srcdir.getDirectoryListing().length > 0){
//				srcdir.copyTo(workdir,true);
//			}
			//*
			for each(var path:String in srcDocuments){
				var srcdir:File = new File(path);
				if(srcdir.exists && srcdir.isDirectory){
					copyCompileFiles(srcdir.getDirectoryListing(), workdir);
				}
			}
			//*/
			
			var sketchPath:File = File.applicationStorageDirectory.resolvePath("scratchTemp/"+projectDocumentName); //*JC*
			
			var projCpp:File = File.applicationStorageDirectory.resolvePath("scratchTemp/"+projectDocumentName+"/"+projectDocumentName+".ino")
				
			
			var outStream:FileStream = new FileStream();
			outStream.open(projCpp, FileMode.WRITE);
			outStream.writeUTFBytes(ccode)
			outStream.close()
			if(ccode.indexOf("updateVar")>-1){
				// aux ino file for serial variable parser
				projCpp = File.applicationStorageDirectory.resolvePath("scratchTemp/"+projectDocumentName+"/MeComm.ino")
				outStream = new FileStream();
				outStream.open(projCpp, FileMode.WRITE);
				outStream.writeUTFBytes(serialParserInoFile)
				outStream.close()
				ccode = ccode.replace("void setup(){",serialParserInoFile+"\nvoid setup(){"); // too tricky here?
			}
			SerialManager.sharedManager().disconnect();
			//UploaderEx.Instance.upload(projCpp.nativePath);
			UploaderEx.Instance.upload(sketchPath.nativePath);
			
			isUploading = true;
			return "";

		}
				
	
		public function get arduinoCliPath():String{
			return File.applicationDirectory.nativePath;// .resolvePath("/").nativePath;
		}
		
		
				
		private function output_onData(event:ProgressEvent):void{
			
			var process:NativeProcess = event.target as NativeProcess;
			
			var info:String = process.standardOutput.readMultiByte(process.standardOutput.bytesAvailable, "gb2312");
			eBlock.app.scriptsPart.appendMessage( info )
			
		}
		
		
		private function get arduinoInstallPath():String{
			if(null == arduinoPath){
				if(Capabilities.os.indexOf("Windows") == 0){
					arduinoPath = File.applicationDirectory.resolvePath("Arduino").nativePath;
				}else{
					arduinoPath = File.applicationDirectory.resolvePath("Arduino/Arduino.app/Contents/Java").nativePath;
				}
			}
			return arduinoPath;
		}
	
		
		private function onOutputData(event:ProgressEvent):void
		{ 
			isUploading = true;
		}
		
		private function onErrorData(event:ProgressEvent):void
		{
			isUploading = true;
			compileErr = true
			var errOut:String = process.standardError.readUTFBytes(process.standardError.bytesAvailable);
			if(null == errorText){
				errorText = errOut;
			}else{
				errorText += errOut;
			}
		}
		
		private function onExit(event:NativeProcessExitEvent):void
		{
			isUploading = false;
			var date:Date = new Date;
			
			eBlock.app.scriptsPart.appendMessage(""+(date.month+1)+"-"+date.date+" "+date.hours+":"+date.minutes+": Process exited with "+event.exitCode);
			numOfSuccess++;
			if(event.exitCode > 0){
				eBlock.app.scriptsPart.appendMsgWithTimestamp(errorText, true);
				errorText = null;
			}
			if(compileErr == false){
				dispatchEvent(new Event(EVENT_NATIVE_DONE));
			}
		}
		
		private var errorText:String;
	}
}