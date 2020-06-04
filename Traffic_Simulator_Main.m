clear all; clc; close all;

numCars = 1;

global highway
laneLength = 500;
numLanes = 2;

highway = Highway(numLanes, 20, laneLength);

writerObj = VideoWriter('Highway Traffic Simulation.avi');
writerObj.FrameRate = 60;

record = 0;

if record
    open(writerObj);
end

% for i = 1:numCars
%     highway.introduce();
% end
dt = .1;

while 1
    highway.update(dt);
    
    if record
        writeVideo(writerObj, getframe(gcf));
    else
        drawnow
    end
    
end

close(writerObj)