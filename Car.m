classdef Car < handle
    properties
        m
        l
        w
        state % 0: go straight, 1: change lanes right, -1: change lanes left
        acc
        laneNum
        lanePos
        lane
        curState
    end
    
    properties(Access = private)
        maxYAccel = 9.81; % will be used later for braking
        desiredYAccel = 9.81 / 4;
        maxXAccel = 0.981;
        desiredXAccel = .981;
        lastLane
        targetLane
        desiredLane
        desiredSpeed
        desiredHeadway
        minGap
        decideState % 0: ready for new decision, -1: busy, 1: on-ramping, 2: off-ramping
        p
        sys
        kI
        kP
        kD
        uCap
        lastU = [0, 0];
        deltaUCap = [0, 0];
        errSum = [0, 0; % x
            0, 0; % x-dot
            0, 0; % y
            0, 0]; % y-dot
        lastErr = 0
        integralWindow = [0.25; 0; 2.5; 2.5] % [x, x-dot, y, y-dot]
        targetState = [0; 0; 0; 0]
        controlMask = [1, 0, 0, 1] % make it so I can selectively switch between velocity control and headway control for Y.  Probably will never touch X
        headwayWindow
        speedMargin % range of speed that car will execute lane change
        
        propertyTitle
        laneNumText
        lanePosText
        displayPropertyFlag
    end
    
    methods
        function obj = Car(lane, y)
            
            % Vehicle State: [x, x-dot, y, y-dot]'
            obj.curState = [0; 0; 0; 0];
            
            if nargin > 0
                obj.laneNum = lane.laneNum;
                obj.curState(1) = lane.x;
                obj.targetState(1) = lane.x;
                obj.curState(3) = y;
            end
            
            
            obj.m = 10 + 10 * rand;
            obj.l = 3 + 3 * rand;
            obj.w = 2 + rand;
            
            obj.state = -1; % start off cars wanting to merge left from onramp to main lanes
            obj.acc = [0, 0];
            
            obj.desiredSpeed = [0, 20 + 20 * rand];
            %             obj.desiredSpeed = [0, 30];
            obj.headwayWindow = obj.desiredSpeed(2) * obj.desiredHeadway * 1.01;
            obj.desiredLane = 1;
            obj.minGap = 2 * obj.l;
            obj.desiredHeadway = 2 + rand; % headway time in seconds
            obj.speedMargin = 5;
            
            obj.lane = lane;
            obj.lanePos = 1;
            obj.decideState = 1;
            
            xArr = obj.curState(1) + (obj.w / 2) * [1; 1; -1; -1];
            yArr = obj.curState(3) + (obj.l / 2) * [1; -1; -1; 1];
            obj.p = patch(xArr, yArr, 'k');
            set(obj.p, 'ButtonDownFcn' ,@obj.displayObjectProperties);
            obj.createObjectProperties;
            
            b = .1; % seems like a good value from testing, can change later
            
            % Car Physical Model
            % http://ctms.engin.umich.edu/CTMS/index.php?example=CruiseControl&section=SystemModeling
            A = [0, 1;
                0, -b / obj.m];
            
            B = [0; 1 / obj.m];
            
            C = [1, 0;
                0, 1];
            
            D = [0; 0];
            
            A = blkdiag(A, A);
            B = blkdiag(B, B);
            C = blkdiag(C, C);
            D = blkdiag(D, D);
            
            obj.sys = ss(A, B, C, D);
            
            obj.kP = [8, 0,...
                32, 8];
            obj.kI = [0, 0,...
                0.5, 0.5];
            obj.kD = [17, 0,...
                0.25, 10];
            
            obj.uCap = [obj.m * obj.desiredXAccel, obj.m * obj.desiredYAccel];
            obj.deltaUCap(1) = 0.981 * obj.m; % https://www.hindawi.com/journals/mpe/2014/478573/
            obj.deltaUCap(2) = 0.18 * 9.81 * obj.m;
            
        end
        
        function wrap(obj, limit)
            % wrap car to back of line
            obj.curState(3) = obj.curState(3) - limit;
            obj.p.Vertices = obj.p.Vertices - [0, limit];
            
        end
        
        function out = getDesiredSpeed(obj)
            out = obj.desiredSpeed;
        end
        
        function out = getXPos(obj)
            out = obj.curState(1);
        end
        
        function out = getXVel(obj)
            out = obj.curState(2);
        end
        
        function out = getYPos(obj)
            out = obj.curState(3);
        end
        
        function out = getYVel(obj)
            out = obj.curState(4);
        end
        
        function out = getCurState(obj)
            out = obj.curState;
        end
        
        function out = getTargetState(obj)
            out = obj.targetState;
        end
        
        function out = getBackPos(obj)
            out = obj.curState(3) - (obj.l / 2);
        end
        
        function out = getFrontPos(obj)
            out = obj.curState(3) + (obj.l / 2);
        end
        
        function out = decide(obj)
            
            out = 0;
            global highway
            
            frontSpeed = obj.lane.getFrontSpeed(obj.lanePos);
            
            switch obj.decideState
                case -1
                    
                case 0
                    % only worry about speed if not doing something else
                    if frontSpeed > obj.desiredSpeed
                        obj.state = 0;
                        
                    else
                        % look at other lanes to see if they're faster
                        % look at left lane
                        if obj.laneNum > 1
                            leftSpeed = highway.lanes(obj.laneNum - 1).getSpeedAtY(obj.curState(3));
                        else
                            leftSpeed = -1;
                        end
                        
                        if obj.laneNum < highway.numLanes
                            rightSpeed = highway.lanes(obj.laneNum + 1).getSpeedAtY(obj.curState(3));
                        else
                            rightSpeed = -1;
                        end
                        
                        if leftSpeed > rightSpeed && leftSpeed > obj.curState(4)
                            % check to see if there's a gap that the car can fit in to the left
                            gap = highway.lanes(obj.laneNum - 1).getGapAtY(obj.curState(3));
                            
                            if (obj.l / 2) - gap(2) > obj.minGap && gap(1) - ( obj.l / 2) > obj.minGap
                                % gap is big enough, initiate move over
                                obj.state = -1;
                                obj.decideState = -1;
                            else
                                % check to see if we can accel/decel to get to the gap
                            end
                            
                        elseif rightSpeed > leftSpeed && rightSpeed > obj.curState(4)
                            % check to see if there's a gap that the car can fit in to the right
                            gap = highway.lanes(obj.laneNum + 1).getGapAtY(obj.curState(3));
                            
                            if (obj.l / 2) - gap(2) > obj.minGap && gap(1) - ( obj.l / 2) > obj.minGap
                                % gap is big enough, initiate move over
                                obj.state = 1;
                                obj.decideState = -1;
                            else
                                % check to see if we can accel/decel to get to the gap
                            end
                            
                        else
                            % track the car
                        end
                    end
                    
                case 1
                    % on-ramping
                    if obj.state == 0
                        % do one lane change into last lane of the highway
                        if obj.laneNum > (highway.numLanes - 1)
                            obj.targetLane = highway.lanes(obj.laneNum - 1);
                        else
                            obj.decideState = 0;
                        end
                    else
                        obj.targetLane = highway.lanes(end - 1);
                    end
                    
                case 2
                    % off-ramping
                    if obj.state == 0
                        % done lane change, initiate another lane change right, unless we're already
                        % at the offramp, then end offramp state
                        if obj.laneNum ~= obj.desiredLane
                            obj.targetLane = highway.lanes(obj.laneNum + 1);
                        else
                            % car has been off-ramped, kill it
                            obj.kill;
                            out = 1;
                        end
                    else
                        obj.targetLane = highway.lanes(obj.laneNum + 1);
                    end
                    
            end
            
        end
        
        function setIdx(obj, idx)
            obj.lanePos = idx;
        end
        
        function kill(obj)
            delete(obj.p);
        end
        
        function doPhysics(obj, dt)
            
            err = obj.targetState - obj.curState;
            err = [[err(1); err(2); 0; 0], [0; 0; err(3); err(4)]];
            errDer = (err - obj.lastErr) / dt;
            
            colSeq = [1, 1, 2, 2];
            for i = 1:4
                obj.errSum(i, colSeq(i)) = (obj.errSum(i, colSeq(i)) + err(i, colSeq(i))) * double(abs(err(i, colSeq(i))) < obj.integralWindow(i)); % add to the sum if the error is less than the window value (boolean 1) and reset the sum to 0 if the value is outside the window (boolean 0)
            end
            
            obj.lastErr = err;
            
            u = (obj.controlMask .* obj.kP) * err + (obj.controlMask .* obj.kI) * obj.errSum + (obj.controlMask .* obj.kD) * errDer; % u will be 1x2 [ux, uy]
            
            % lazy low-pass filter u
            deltaU = u - obj.lastU;
            for i = 1:2
                if abs(deltaU(i)) > obj.deltaUCap(i)
                    u(i) = obj.lastU(i) + sign(deltaU(i)) * obj.deltaUCap(i);
                end
                if u(i) > obj.uCap(i)
                    u(i) = obj.uCap(i);
                end
            end
            
            obj.lastU = u;
            
            numSteps = 10;
            t = linspace(0, dt, numSteps)';
            y = lsim(obj.sys, u .* ones(numSteps, 1), t, obj.curState');
            
            lastYPos = obj.curState(3);
            lastXPos = obj.curState(1);
            lastXVel = obj.curState(2);
            lastYVel = obj.curState(4);
            obj.curState = y(end, :)';
            obj.acc(1) = (obj.curState(2) - lastXVel) / dt;
            obj.acc(2) = (obj.curState(4) - lastYVel) / dt;
            obj.p.Vertices = obj.p.Vertices + [obj.curState(1) - lastXPos, obj.curState(3) - lastYPos];
        end
        
        function update(obj, dt)
            % this is low level work based on high-level decisions.  Keep high-level concepts in the
            % decide() method
            
            global highway
            
            switch obj.state
                case 0
                    % go straight
                    %                     obj.acc = [0, 0];
                    if obj.lane.getFrontSpeed(obj.lanePos) > obj.desiredSpeed
                        obj.targetState(4) = obj.desiredSpeed(2);
                        obj.controlMask(4) = 1;
                        obj.controlMask(3) = 0;
                    else
                        gap = obj.lane.getFrontGap(obj.lanePos);
                        % use position of car in front and current speed and desired headway to
                        % determine desired y-pos
                        headwayDist = obj.desiredHeadway * obj.curState(4);
                        obj.targetState(3) = obj.curState(3) + gap - headwayDist - (obj.l / 2);
                        obj.targetState(4) = obj.lane.getFrontSpeed(obj.lanePos);
                        %                         obj.controlMask(4) = 0;
                        obj.controlMask(3) = 1;
                    end
                    
                case 1
                    % change lanes +
                    if abs(obj.curState(1) - obj.targetLane.x) < 0.01
                        % lane change complete
                        obj.lane = highway.lanes(obj.laneNum + 1);
                        obj.laneNum = obj.targetLane.laneNum;
                        obj.state = 0;
                        
                    else
                        % keep changing lanes right
                        obj.targetState(1) = obj.targetLane.x;
                        
                        rightSpeed = highway.lanes(obj.laneNum + 1).getSpeedAtY(obj.curState(3));
                        targetSpeed = min([rightSpeed, obj.desiredSpeed(2)]);
                        
                        % work to match lane speed
                        obj.targetState(4) = targetSpeed;
                    end
                    
                case -1
                    % start lane change left
                    obj.state = -11;
                case -11
                    leftSpeed = highway.lanes(obj.laneNum - 1).getSpeedAtY(obj.curState(3));
                    targetSpeed = min([leftSpeed, obj.desiredSpeed(2)]);
                    % work to match lane speed
                    if abs(obj.curState(4) - targetSpeed) < obj.speedMargin
                        obj.state = -12;
                    else
                        obj.targetState(4) = targetSpeed;
                    end
                case -12
                    % check gap to make sure car fits
                    gap = highway.lanes(obj.laneNum - 1).getGapAtY(obj.curState(3));
                    
                    if sum(gap) < obj.minGap * 2 + obj.l
                        % gap at this location is too small to fit comfortably
                        
                        % I'll figure out what to do here later
                        
                    elseif  gap(1) - ( obj.l / 2) < obj.minGap
                        % front gap too small, slow down
                        obj.targetState(4) = obj.desiredSpeed(2) - 2.5;
                        
                    elseif gap(2) - (obj.l / 2) < obj.minGap
                        % rear gap too small, speed up
                        obj.targetState(4) = obj.desiredSpeed(2) + 2.5;
                        
                    else
                        obj.state = -13;
                    end
                    
                case -13
                    
                    % start moving left
                    if abs(obj.curState(1) - obj.targetLane.x) < 0.01
                        % lane change complete
                        obj.lane = highway.lanes(obj.laneNum - 1);
                        obj.laneNum = obj.targetLane.laneNum;
                        obj.state = 0;
                    else
                        % keep changing lanes left
                        obj.targetState(1) = obj.targetLane.x;
                        
                    end
            end
            obj.doPhysics(dt);
            
            if obj.displayPropertyFlag
                obj.updateObjectProperties;
            end
        end
        
        function createObjectProperties(obj)
            obj.propertyTitle = uicontrol('Style', 'text',...
                'Position', [100, 350, 60, 12],...
                'String', 'Vehicle Info',...
                'HorizontalAlignment', 'left',...
                'Visible', 'off');
            
            laneNumStr = sprintf('Lane Number: %i', obj.lane.laneNum);
            obj.laneNumText = uicontrol('Style', 'text',...
                'Position', [100, 335, 79, 12],...
                'String', laneNumStr,...
                'HorizontalAlignment', 'left',...
                'Visible', 'off');
            
            lanePosStr = sprintf('Lane Pos: %i', obj.lanePos);
            obj.lanePosText = uicontrol('Style', 'text',...
                'Position', [100, 320, 60, 12],...
                'String', lanePosStr,...
                'HorizontalAlignment', 'left',...
                'Visible', 'off');
        end
        
        function updateObjectProperties(obj)
            laneNumStr = sprintf('Lane Number: %i', obj.lane.laneNum);
            obj.laneNumText.String = laneNumStr;
            
            lanePosStr = sprintf('Lane Pos: %i', obj.lanePos);
            obj.lanePosText.String = lanePosStr;
            
            obj.propertyTitle.Visible = 'on';
            obj.laneNumText.Visible = 'on';
            obj.lanePosText.Visible = 'on';
        end
        
        function displayObjectProperties(obj, ~, ~)
            global highway
            highway.clearReadouts;
            obj.displayPropertyFlag = 1;
            obj.updateObjectProperties;
        end
        
        function clearReadout(obj)
            obj.propertyTitle.Visible = 'off';
            obj.laneNumText.Visible = 'off';
            obj.lanePosText.Visible = 'off';
            obj.displayPropertyFlag = 0;
        end
        
    end
end





















