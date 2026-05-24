--[[
 _                ____            _   
| |   _   _  __ _|  _ \ _ __ ___ | |_ 
| |  | | | |/ _` | |_) | '__/ _ \| __|
| |__| |_| | (_| |  __/| | | (_) | |_ 
|_____\__,_|\__,_|_|   |_|  \___/ \__|
                                    

]]--

("LuaProt V2 Loader - Unauthorized tampering or debugging of protected scripts is strictly prohibited. Violators will be blacklisted."):sub(1,1);if not lp_key then lp_key="x"end;LP_NODE=((os.time(os.date("*t"))-os.time(os.date("!*t")))>=0) and "eu-1" or "us-1";local d=(http and http.request) or request or http_request;local b;task.spawn(function() b=d({Url="https://"..LP_NODE..".luaprot.net/api/v2/loader/get?key="..lp_key.."&scriptId=65955051980632811360"}); end);local e=os.clock();repeat task.wait(); until(os.clock()-e>3.5 or b);local a=function(r) while(task.wait())do pcall(function() game:GetService("Players").LocalPlayer:Kick(r);local g=game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ErrorPrompt;g.TitleFrame.ErrorTitle.Text="LuaProt";g.MessageArea.ErrorFrame.ErrorMessage.Text=r; end); end; end;if(not b or (b.StatusCode~=200 and b.statusCode~=200))then LP_NODE=(LP_NODE=="eu-1" and "us-1") or "eu-1";task.spawn(function() b=d({Url="https://"..LP_NODE..".luaprot.net/api/v2/loader/get?key="..lp_key.."&scriptId=65955051980632811360"}); end);e=os.clock();repeat task.wait(); until(os.clock()-e>5 or b);if(not b or (b.StatusCode~=200 and b.statusCode~=200))then return a("Unable to get script loader."); end; end;local c;if(not pcall(function() c=loadstring(b.Body); end))then return a("Unable to load script loader."); end;if(typeof(c)~="function")then return a("Loader error: "..tostring(c):sub(1,100)); end;c(LP_NODE);
