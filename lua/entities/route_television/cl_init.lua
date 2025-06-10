include('shared.lua')

local htmlCache = {} -- Кэш для HTML страниц
local prefix = "informator."..game.GetMap()..".playline.route"
local L = Trolleybus_System.GetLanguagePhrase
local LN = Trolleybus_System.GetLanguagePhraseName

function ENT:GetRouteStops(routeID)
    if not Trolleybus_System.GetInformators then return nil end
    
    local stops = {}
    local informators = Trolleybus_System.GetInformators()
    local routeKey = prefix..routeID
    
    for k,v in pairs(informators) do
        if type(k) == "string" and k:find(routeKey..".", 1, true) then
            local stopKey = k:sub(#routeKey+2)
            local stopName, stopType = stopKey:match("^(.-)%.(.+)$")
            
            if stopName and stopType then
                if not stops[stopName] then
                    stops[stopName] = {}
                end
                stops[stopName][stopType] = v
            end
        end
    end
    
    return stops
end

function ENT:GetRouteEndpoints(routeID)
    local stops = self:GetRouteStops(routeID)
    if not stops or not next(stops) then return nil, nil end
    
    local firstStop, lastStop
    local stopNames = {}
    
    for stopName in pairs(stops) do
        table.insert(stopNames, stopName)
    end
    
    table.sort(stopNames)
    
    for i, stopName in ipairs(stopNames) do
        local data = stops[stopName]
        
        if data.arrival and data.arrival:find("%[Конечная%]") then
            lastStop = data.arrival:gsub("%[Конечная%]", ""):Trim()
            if not firstStop and i > 1 then
                firstStop = stops[stopNames[1]].departure or stops[stopNames[1]].arrival
                firstStop = firstStop:gsub("%[Отправление%]", ""):gsub("%[Прибытие%]", ""):Trim()
            end
        elseif data.departure and data.departure:find("%[Конечная%]") then
            firstStop = data.departure:gsub("%[Конечная%]", ""):Trim()
            if not lastStop and i < #stopNames then
                lastStop = stops[stopNames[#stopNames]].arrival or stops[stopNames[#stopNames]].departure
                lastStop = lastStop:gsub("%[Прибытие%]", ""):gsub("%[Отправление%]", ""):Trim()
            end
        end
    end
    
    if not firstStop and #stopNames > 0 then
        firstStop = stops[stopNames[1]].departure or stops[stopNames[1]].arrival
        firstStop = firstStop and firstStop:gsub("%[Отправление%]", ""):gsub("%[Прибытие%]", ""):Trim() or ""
    end
    
    if not lastStop and #stopNames > 0 then
        lastStop = stops[stopNames[#stopNames]].arrival or stops[stopNames[#stopNames]].departure
        lastStop = lastStop and lastStop:gsub("%[Прибытие%]", ""):gsub("%[Отправление%]", ""):Trim() or ""
    end
    
    return firstStop, lastStop
end

function ENT:GetRouteInfo()
    if not Trolleybus_System then return "00", "", "" end
    
    local parent = self:GetParent()
    if not IsValid(parent) then return "00", "", "" end

    local routeID
    
    if parent.GetSystem then
        local nameplates = parent:GetSystem("Nameplates")
        if nameplates and nameplates.GetRoute then
            routeID = nameplates:GetRoute(1)
        end

        local agit132 = parent:GetSystem("Agit-132")
        if agit132 and agit132.GetRoute then
            routeID = agit132:GetRoute(1)
        end
    end

    if not routeID then return "00", "", "" end
    
    -- Пробуем получить информацию из системы маршрутов
    if Trolleybus_System.Routes then
        local routeName = Trolleybus_System.Routes.GetRouteName(routeID) or routeID
        local startStop = Trolleybus_System.Routes.GetRouteStart(routeID) or ""
        local endStop = Trolleybus_System.Routes.GetRouteEnd(routeID) or ""
        
        if startStop ~= "" and endStop ~= "" then
            return routeName, startStop, endStop
        end
    end
    
    -- Если в системе маршрутов нет данных, используем старый метод
    local firstStop, lastStop = self:GetRouteEndpoints(routeID)
    local routeName = Trolleybus_System.Routes and Trolleybus_System.Routes.GetRouteName(routeID) or routeID
    
    return routeName, firstStop or "", lastStop or ""
end

function ENT:UpdateRouteInHTML(routeName, firstStop, lastStop)
    if IsValid(self.htmlPanel) then
        self.htmlPanel:QueueJavascript(string.format([[
            if (window.updateRouteInfo) {
                updateRouteInfo('%s', '%s', '%s');
            }
        ]], routeName, firstStop or "", lastStop or ""))
    end
end

function ENT:UpdateStopInHTML(stopText)
    if IsValid(self.htmlPanel) then
        self.htmlPanel:QueueJavascript(string.format([[
            if (window.updateStopName) {
                updateStopName('%s');
            }
        ]], stopText:gsub("'", "\\'")))
    end
end

function ENT:GetStopText()
    local parent = self:GetParent()
    if not IsValid(parent) then return "" end

    -- Проверяем наличие системы Agit-132 и метода GetStopText
    if parent.GetSystem then
        local agit132 = parent:GetSystem("Agit-132")
        if agit132 and agit132.GetStopText then
            local stopText = agit132:GetStopText() or "Остановка не инициализирована"
            
            -- Функция для удаления лишних пробелов
            local function trim(s)
                return s:gsub("^%s*(.-)%s*$", "%1")
            end
            
            -- Обработка текста остановки
            if stopText:find("%[Отправление%]") then
                return "Текущая остановка: " .. trim(stopText:gsub("%[Отправление%]", ""))
            elseif stopText:find("%[Прибытие%]") then
                return "Следующая остановка: " .. trim(stopText:gsub("%[Прибытие%]", ""))
            else
                return stopText
            end
        end
    end

    return ""
end

function ENT:Draw()
    if not IsValid(self) then return end
    self:DrawModel()    
    local pos, ang = self:LocalToWorld(Vector(0.55,-11.56,6.142)), self:GetAngles() + Angle(0, 90, 92.4)
    local dist = LocalPlayer():EyePos():Distance(self:GetPos())
    local viewdist = 170
    local viewdistmax = viewdist
    local viewdistmin = viewdist * 0.80
    local monitorX, monitorY = 1361, 720

    local alpha = 0

    if dist < viewdistmin then
        alpha = 255
    elseif dist > viewdistmax then
        alpha = 0 
    else
        alpha = 255 * (1 - (dist - viewdistmin) / (viewdistmax - viewdistmin))
    end

    local routeName, firstStop, lastStop = self:GetRouteInfo()
    self.currentRouteName = self.currentRouteName or "00"
    self.currentFirstStop = self.currentFirstStop or ""
    self.currentLastStop = self.currentLastStop or ""

    if self.currentRouteName ~= routeName or self.currentFirstStop ~= firstStop or self.currentLastStop ~= lastStop then
        self.currentRouteName = routeName
        self.currentFirstStop = firstStop
        self.currentLastStop = lastStop
        self:UpdateRouteInHTML(routeName, firstStop, lastStop)
    end

    local stopText = ""
    if self.GetStopText then
        stopText = self:GetStopText() or ""
    end
    self.currentStopText = self.currentStopText or ""

    if self.currentStopText ~= stopText then
        self.currentStopText = stopText
        self:UpdateStopInHTML(stopText)
    end
    
    if alpha > 0 then
        cam.Start3D2D(pos, ang, 0.017)
            if not IsValid(self.htmlPanel) then
                self.htmlPanel = vgui.Create("DHTML")
                self.htmlPanel:SetSize(monitorX, monitorY)
                self.htmlPanel:SetPaintedManually(true)

                local url = self:GetNWString("HTML_URL", "https://laser-navy-packet.glitch.me")
                
                if htmlCache[url] then
                    self.htmlPanel:SetHTML(htmlCache[url])
                else
                    self.htmlPanel:OpenURL(url)
                    self.htmlPanel:AddFunction("console", "cache", function(html)
                        htmlCache[url] = html
                    end)
                end
                
                self.htmlPanel:QueueJavascript([[
                    window.updateRouteInfo = function(routeNum, firstStop, lastStop) {
                        let routeElement = document.getElementById('route-number');
                        if(routeElement) routeElement.textContent = 'Маршрут №: ' + routeNum;
                        
                        let routePathElement = document.getElementById('route-path');
                        if(routePathElement) routePathElement.textContent = firstStop + '  -  ' + lastStop;
                    };
                    
                    window.updateStopName = function(stopText) {
                        let stopElement = document.getElementById('stop-name');
                        if(stopElement) stopElement.textContent = stopText;
                    };
                ]])
                
                self:UpdateRouteInHTML(self.currentRouteName, self.currentFirstStop, self.currentLastStop)
            end
            
            self.htmlPanel:PaintManual()
        cam.End3D2D()
    end
end

function ENT:OnRemove()
    if IsValid(self.htmlPanel) then
        self.htmlPanel:Remove()
    end
end
